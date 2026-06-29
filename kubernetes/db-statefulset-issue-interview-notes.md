# Interview Prep: Kubernetes Database StatefulSet Stuck in Pending (RCA & Resolution)

Use this document to prepare for interview questions about troubleshooting Kubernetes storage classes, stateful applications, and debugging persistent volume claims (PVCs) in EKS.

---

## 1. Problem Statement
The database microservice (running Postgres via a Kubernetes StatefulSet) failed to start up in the EKS cluster. The pods remained stuck in the **`Pending`** status:

```bash
$ kubectl get pods -n jerney-ns
NAME               READY   STATUS    RESTARTS   AGE
db-statefulset-0   0/1     Pending   0          74s
```

Investigating the PersistentVolumeClaims (PVCs) created by the StatefulSet's volume claim templates revealed that the PVC was also stuck in a **`Pending`** state:

```bash
$ kubectl get pvc -n jerney-ns
NAME                          STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS           VOLUMEATTRIBUTESCLASS   AGE
db-storage-db-statefulset-0   Pending                                      jerney-storage-class   <unset>                 86s
```

Describing the PVC (`kubectl describe pvc db-storage-db-statefulset-0 -n jerney-ns`) displayed the following warning events:
```
Events:
  Type    Reason                Age               From                         Message
  ----    ------                ----              ----                         -------
  Normal  WaitForFirstConsumer  93s               persistentvolume-controller  waiting for first consumer to be created before binding
  Normal  ExternalProvisioning  5s (x7 over 93s)  persistentvolume-controller  Waiting for a volume to be created either by the external provisioner 'ebs.csi.eks.amazonaws.com' or manually by the system administrator. If volume creation is delayed, please verify that the provisioner is running and correctly registered.
```

---

## 2. Root Cause Analysis (RCA)
The issue occurred due to a misconfiguration in the StorageClass resource definition ([10-storageClass.yml](file:///home/ubuntu/Jerney/kubernetes/10-storageClass.yml)):

1. **Incorrect Provisioner Name:**
   The `provisioner` field inside the StorageClass manifest was set to `ebs.csi.eks.amazonaws.com`:
   ```yaml
   provisioner: ebs.csi.eks.amazonaws.com
   ```
2. **CSI Driver Name Mismatch:**
   In AWS EKS, the default AWS EBS CSI driver registers itself in the cluster under the name **`ebs.csi.aws.com`**.
   Since Kubernetes matches PVC dynamic provisioning requests to CSI controllers using the exact provisioner string, the EBS CSI provisioner did not recognize or process any volume requests meant for `ebs.csi.eks.amazonaws.com`. This left the PVC pending indefinitely.

---

## 3. How It Was Fixed
The resolution was implemented in a four-step workflow:

1. **Updated the StorageClass Manifest:**
   We modified the StorageClass manifest ([10-storageClass.yml](file:///home/ubuntu/Jerney/kubernetes/10-storageClass.yml)) to specify the correct provisioner name:
   ```diff
   -provisioner: ebs.csi.eks.amazonaws.com
   +provisioner: ebs.csi.aws.com
   ```

2. **Recreated the StorageClass:**
   Because the `provisioner` field is immutable on existing Kubernetes StorageClass resources, attempts to directly `apply` the change failed. We deleted the existing resource and recreated it:
   ```bash
   kubectl delete sc jerney-storage-class
   kubectl apply -f kubernetes/10-storageClass.yml
   ```

3. **Re-Initialized the StatefulSet and PVCs:**
   To force the StatefulSet to request a new volume using the updated StorageClass configuration:
   * Scaled the StatefulSet replicas down to `0`:
     ```bash
     kubectl scale statefulset db-statefulset -n jerney-ns --replicas=0
     ```
   * Deleted the old pending PVC:
     ```bash
     kubectl delete pvc db-storage-db-statefulset-0 -n jerney-ns
     ```
   * Scaled the StatefulSet back up to `3` replicas:
     ```bash
     kubectl scale statefulset db-statefulset -n jerney-ns --replicas=3
     ```

4. **Verified the Rollout:**
   * Monitored the PVC and Pod status:
     ```bash
     kubectl get pods,pvc -n jerney-ns
     ```
   * Verified that the PVC dynamically provisioned and bound successfully.
   * Confirmed all 3 replicas (`db-statefulset-0`, `db-statefulset-1`, and `db-statefulset-2`) reached a healthy `Running` and `Ready` state.

---

## 4. Interview-Ready Talking Points
If asked: *"Tell me about a time you debugged a Kubernetes storage or StatefulSet issue."*

* **Start with the Symptom**: "I encountered an issue where our database StatefulSet pods were stuck in a `Pending` state during deployment."
* **Walk through Troubleshooting**: "I started by checking the pod status and describing the pod, which showed it was waiting for its volume. I then inspected the corresponding PersistentVolumeClaim (PVC) and saw it was pending. Running a `kubectl describe pvc` revealed that the persistentvolume-controller was waiting for the external provisioner `ebs.csi.eks.amazonaws.com` to create the volume."
* **Explain the RCA**: "I checked the registered CSI drivers in the cluster using `kubectl get csidrivers` and noticed the AWS EBS CSI driver was registered as `ebs.csi.aws.com`. However, our StorageClass manifest had a typo and was configured to use `ebs.csi.eks.amazonaws.com`. Because of the mismatch, the CSI controller was not receiving the provisioning requests."
* **Explain the Fix**: "Since StorageClass provisioner fields are immutable, I deleted and recreated the StorageClass with the correct `ebs.csi.aws.com` provisioner name. To clean up the state, I scaled the StatefulSet down to `0`, deleted the stale pending PVC, and scaled the StatefulSet back up. The new PVC bound instantly, and the StatefulSet rolled out successfully with all three pods in a `Running` and `Ready` state."
