1) ubuntu@ip-172-31-4-232:~/Jerney/kubernetes$ kubectl get pods -n jerney-ns
NAME                                   READY   STATUS                       RESTARTS   AGE
frontend-deployment-5d8697b4f5-2g854   0/1     CreateContainerConfigError   0          57s
frontend-deployment-5d8697b4f5-x6lpw   0/1     CreateContainerConfigError   0          57s

Error: container has runAsNonRoot and image has non-numeric user (nginx), cannot verify user is non-root 

What Kubernetes is saying:
Your pod security config says:
👉 “This container MUST NOT run as root”
But your image says:
👉 “User = nginx” (string, not numeric UID)
Kubernetes cannot verify if nginx is root or not
👉 So it blocks the container from starting

Kubernetes security works like this:

If you use:
securityContext:
  runAsNonRoot: true

Then Kubernetes expects:

✔ A numeric user ID (like 1000)
❌ Not a string like nginx

Because:
It only trusts numeric UID


Fix Options (choose one)
✔️ Option 1 (BEST PRACTICE): Set numeric UID in Deployment

Update your deployment:

securityContext:
  runAsNonRoot: true
  runAsUser: 101

👉 101 is typically the UID for nginx

✔️ Option 2: Fix Dockerfile (cleaner long-term)

Instead of: USER nginx

Use:

USER 101


🔍 How to confirm UID inside image

You can check:
docker run --rm your-image id nginx
or:
docker run --rm your-image cat /etc/passwd

You’ll likely see:
nginx:x:101:101:...

Interview-ready explanation

My frontend pods failed with CreateContainerConfigError due to a securityContext enforcing runAsNonRoot. 
The container image used a named user instead of a numeric UID, which Kubernetes could not validate. 
I resolved it by explicitly setting runAsUser to the correct UID for nginx.

---

2) db-statefulset in Pending state

Analysis & Root Cause:
The database StatefulSet pods were stuck in a `Pending` state because the dynamic volume provisioning for the PersistentVolumeClaim (PVC) failed.
The StorageClass `jerney-storage-class` had the `provisioner` property set to `ebs.csi.eks.amazonaws.com`.
However, the AWS EBS CSI driver registered in the cluster uses the standard provisioner name `ebs.csi.aws.com`.
Because the provisioner names did not match, Kubernetes could not dynamically provision the EBS volume for the PVC, leaving both the PVC and the dependent StatefulSet pods permanently in a `Pending` status.

Fix Implementation:
1. Modified the StorageClass definition in [10-storageClass.yml](file:///home/ubuntu/Jerney/kubernetes/10-storageClass.yml) to use the correct provisioner `ebs.csi.aws.com`.
2. Deleted and recreated the StorageClass in the cluster since provisioner updates on an existing StorageClass are forbidden.
3. Scaled down the StatefulSet to `0`, deleted the stale pending PVC, and scaled the StatefulSet back up to `3` to trigger a clean dynamic volume provisioning cycle under the updated StorageClass.

All 3 replicas successfully provisioned their volumes, bound their PVCs, and transitioned to a healthy `Running` and `Ready` status.

For a detailed walkthrough, RCA, and interview talking points, see [db-statefulset-issue-interview-notes.md](file:///home/ubuntu/Jerney/kubernetes/db-statefulset-issue-interview-notes.md).

---

3) Intermittent /api/posts data loading failure

Analysis & Root Cause:
The frontend page would intermittently show data on one refresh and show nothing on the next. The API call to `/api/posts` was failing inconsistently.

The HTTPRoute in `12-http-routes.yml` had two rules:
- `/api` → `backend-service:5000` (direct to backend)
- `/` → `frontend-service:8080` (through nginx)

Meanwhile, the backend NetworkPolicy in `14-networkPolicyBackend.yml` only allows ingress from pods labeled `app.kubernetes.io/name: frontend-deployment`.

When the browser's XHR request to `/api/posts` hit the Gateway, the HTTPRoute matched the `/api` prefix and routed it **directly to the backend**, bypassing the frontend nginx pods. The source of this traffic was the **gateway pod**, which does NOT carry the `frontend-deployment` label — so the NetworkPolicy **blocked** the request.

The behavior was intermittent because on some refreshes the SPA routing or browser caching caused the request path to vary, and the gateway's load balancing across pods added further inconsistency.

Secondary issue: The ConfigMap in `02-configmap.yml` had `DB_PORT` defined twice — once as `"5000"` and once as `"5432"`. The `"5000"` entry was actually the Express server PORT, not a database port.

Fix Implementation:
1. Removed the `/api` → `backend-service` route from `12-http-routes.yml`. All traffic now flows through the frontend nginx pods, which already have a `proxy_pass` rule in `nginx.conf` that forwards `/api/*` requests to `backend-service:5000`. This path is allowed by the NetworkPolicy since the source pod IS a frontend pod.
2. Renamed the misnamed `DB_PORT: "5000"` to `PORT: "5000"` in the ConfigMap to correctly reflect it is the Express server port, not a database port.

Interview-ready explanation:

The frontend was intermittently failing to load data from `/api/posts`. I traced it to a conflict between the Gateway API HTTPRoute and a backend NetworkPolicy. The HTTPRoute had a rule that sent `/api/*` traffic directly to the backend service, bypassing the frontend nginx reverse proxy. However, the backend's NetworkPolicy only allowed ingress from frontend-labeled pods. Since the gateway pods didn't carry that label, those direct requests were blocked. The fix was to remove the redundant `/api` route from the HTTPRoute, so all traffic flows through nginx's `proxy_pass`, which the NetworkPolicy correctly allows. This also simplified the routing to a single entry point, which is a better architectural pattern.

