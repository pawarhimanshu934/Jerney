# Interview Prep: Kubernetes Frontend Pod Crash Loop (RCA & Resolution)

Use this document to prepare for interview questions about troubleshooting Kubernetes deployments, container security, and debugging production-like issues.

---

## 1. Problem Statement
The frontend microservice (running Nginx to serve static React/Vite assets and proxy API requests) failed to start up in the EKS cluster. The pods immediately entered a **`CrashLoopBackOff`** state after restarting:

```bash
$ kubectl get pods -n jerney-ns
NAME                                   READY   STATUS             RESTARTS      AGE
frontend-deployment-7fc868768-bxb24    0/1     CrashLoopBackOff   7 (74s ago)   12m
```

Looking at the pod events and logs from the terminated container (`kubectl logs <pod-name> -n jerney-ns --previous`), Nginx was failing to initialize with the following error:
```
nginx: [emerg] bind() to 0.0.0.0:80 failed (13: Permission denied)
```

---

## 2. Root Cause Analysis (RCA)
The issue occurred due to a conflict between **Kubernetes Security Context constraints** and the **Nginx container network configuration**:

1. **Security Context Restricting Root Access:**
   To follow DevSecOps best practices, the Kubernetes deployment manifest ([04-frontend-deployment.yml](file:///home/ubuntu/Jerney/kubernetes/04-frontend-deployment.yml)) configured the pod's `securityContext` to enforce non-root execution:
   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 101 # nginx user UID
   ```
   This forced the container to run strictly as the unprivileged `nginx` user (UID `101`).

2. **Privileged Port Bind Attempt:**
   By default, standard Nginx configs try to listen on port `80`. In Linux/Unix-like operating systems, binding to any port below `1024` (privileged ports) requires **root/superuser privileges**. Since the container was running as UID `101` (non-root), the OS kernel blocked Nginx from binding to port `80`, resulting in a `Permission Denied` error and instant termination.

3. **Stale Image Cache (Secondary Issue):**
   Although a code change had been committed to update the local [frontend/nginx.conf](file:///home/ubuntu/Jerney/frontend/nginx.conf) to listen on port `8080`, the remote Docker image tag (`:himanshu`) deployed in the cluster was not successfully updated or pulled. The default `imagePullPolicy` was set to `IfNotPresent`, which caused the Kubernetes nodes to reuse the old cached image that still bound to port `80`.

---

## 3. How It Was Fixed
The resolution was implemented in a three-step workflow:

1. **Rebuilt and Pushed the Docker Image:**
   We confirmed the local configuration files were updated:
   * Updated the Nginx server block to use an unprivileged port: `listen 8080;` in [frontend/nginx.conf](file:///home/ubuntu/Jerney/frontend/nginx.conf).
   * Updated the container port exposure to `EXPOSE 8080` in the [Dockerfile](file:///home/ubuntu/Jerney/frontend/Dockerfile).
   * Rebuilt the Docker image locally and pushed it to the GitHub Container Registry (`ghcr.io`) using the updated configuration.

2. **Updated the Deployment Pull Policy:**
   We modified the Kubernetes Deployment manifest ([04-frontend-deployment.yml](file:///home/ubuntu/Jerney/kubernetes/04-frontend-deployment.yml)) to specify `imagePullPolicy: Always`. This ensures that even when using mutable tags (like `:himanshu` or `:latest`), Kubernetes always pulls the newest version of the image from the registry rather than using cached node copies.
   ```yaml
         containers:
         - name: frontend-container
           image: ghcr.io/pawarhimanshu934/jerney/jerney-frontend:himanshu
           imagePullPolicy: Always
   ```

3. **Applied and Verified the Rollout:**
   * Applied the new deployment file using `kubectl apply`.
   * Monitored the rollout status (`kubectl rollout status`).
   * Confirmed that both new replicas started successfully, bound to port `8080`, passed liveness/readiness health checks, and old failing replicas were terminated.

---

## 4. Interview-Ready Talking Points
If an interviewer asks: *"Tell me about a time you had to debug a failing application in production/Kubernetes."*

* **Start with the Symptom**: "I encountered a `CrashLoopBackOff` issue with a frontend container serving static React assets via Nginx in an EKS cluster."
* **Walk through Troubleshooting**: "I started by running `kubectl describe` and checking the logs of the previous container execution (`kubectl logs --previous`). The log clearly showed `nginx: [emerg] bind() to 0.0.0.0:80 failed (13: Permission denied)`."
* **Explain the RCA (The 'Aha!' Moment)**: "I connected the dots between our security policy and the Nginx config. The deployment template was running the container as an unprivileged UID (`101`) to comply with non-root security standards, but Nginx was trying to bind to port `80`. In Linux, binding to ports below `1024` requires root privileges."
* **Explain the Fix**: "We updated the Nginx configuration to listen on port `8080` and exposed port `8080` in the Dockerfile. I also noticed that the cluster was caching an older image on the nodes, so I updated the deployment manifest's `imagePullPolicy` to `Always` to guarantee the cluster picked up the newly pushed image. We rolled out the update, and the pods successfully went into `Running` status and passed their health checks."
* **Share the Lesson Learned**: "This taught me to always pair non-root `securityContext` settings in Kubernetes manifests with high-number listening ports (like 8080 or 8082) in the container config, and to explicitly manage image pull policies on dev/testing branches."


Summary of What Was Done:
Diagnosis: The initial crash occurred because the frontend containers were configured to run as non-root (runAsNonRoot: true, runAsUser: 101), but the Docker image ghcr.io/pawarhimanshu934/jerney/jerney-frontend:himanshu inside the EKS cluster was configured to listen on port 80 (a privileged port requiring root). This led to a Permission denied error when trying to bind to port 80.

Rebuilding the Image: Since your local codebase had already been modified to use port 8080 in frontend/nginx.conf, I logged into the container registry and rebuilt the Docker image locally, packaging the correct port configuration (listen 8080). I then pushed this image to ghcr.io.

Updating the Kubernetes Manifest: To force Kubernetes to pull the newly built image instead of using the older cached image tag, I added imagePullPolicy: Always to the frontend container specification in 04-frontend-deployment.yml.

Deploying: I applied the updated manifest and successfully rolled out the deployment. The new pods started up successfully on port 8080 under the non-root user.
