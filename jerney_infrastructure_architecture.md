# Jerney — Complete Infrastructure Architecture

> **Project**: Jerney Blog Platform — A 3-tier web application deployed on AWS EKS using Terraform, Kubernetes, and GitHub Actions CI/CD.

---

## 1. High-Level Architecture Overview

```mermaid
graph TB
    subgraph "Developer Workflow"
        DEV["👨‍💻 Developer"]
        GH["GitHub Repository"]
    end

    subgraph "CI/CD Pipeline — GitHub Actions"
        LINT["Stage 1: ESLint"]
        SCA["Stage 2: npm audit (SCA)"]
        BUILD["Stage 3: Docker Build & Push"]
        TRIVY["Stage 4: Trivy Image Scan"]
    end

    subgraph "Container Registry"
        GHCR["GitHub Container Registry (GHCR)"]
    end

    subgraph "Infrastructure as Code"
        TF["Terraform"]
    end

    subgraph "AWS Cloud — us-east-1"
        subgraph "VPC 10.0.0.0/16"
            subgraph "Public Subnets (3 AZs)"
                NAT["NAT Gateway"]
                IGW["Internet Gateway"]
            end
            subgraph "Private Subnets (3 AZs)"
                EKS["EKS Cluster v1.33"]
            end
        end
    end

    DEV -->|"git push"| GH
    GH -->|"triggers"| LINT
    LINT --> SCA
    SCA --> BUILD
    BUILD -->|"pushes images"| GHCR
    BUILD --> TRIVY
    GHCR -->|"pulls images"| EKS
    TF -->|"provisions"| EKS
    IGW --> NAT
    NAT --> EKS
```

---

## 2. AWS Cloud Infrastructure (Terraform Layer)

> Provisioned via [terraform/](file:///home/ubuntu/Jerney/terraform) using official AWS modules.

```mermaid
graph TB
    subgraph "AWS Account — us-east-1"
        subgraph "VPC: Jerney-vpc (10.0.0.0/16)"
            IGW["Internet Gateway"]
            
            subgraph "Public Subnets (/20 each)"
                PUB1["10.0.48.0/20<br/>us-east-1a"]
                PUB2["10.0.64.0/20<br/>us-east-1b"]
                PUB3["10.0.80.0/20<br/>us-east-1c"]
                NAT["NAT Gateway<br/>(Single, cost-saving)"]
            end
            
            subgraph "Private Subnets (/20 each)"
                PRIV1["10.0.0.0/20<br/>us-east-1a"]
                PRIV2["10.0.16.0/20<br/>us-east-1b"]
                PRIV3["10.0.32.0/20<br/>us-east-1c"]
            end
            
            subgraph "EKS Cluster: Jerney (v1.33)"
                CP["Control Plane<br/>(AWS Managed)"]
                
                subgraph "Managed Node Group"
                    NG["jerney-node-group<br/>t3.medium (SPOT)<br/>1 node, 30GB disk<br/>AMI: AL2023"]
                end
                
                subgraph "EKS Add-ons"
                    DNS["CoreDNS"]
                    CNI["VPC CNI"]
                    KP["kube-proxy"]
                    PI["EKS Pod Identity Agent"]
                end
            end
        end
    end

    IGW --> NAT
    NAT --> PRIV1
    NAT --> PRIV2
    NAT --> PRIV3
    CP --> NG
```

### Terraform Configuration Summary

| Resource | Source | Key Settings |
|---|---|---|
| **VPC** | `terraform-aws-modules/vpc/aws` | 3 AZs, NAT Gateway (single), public/private subnets |
| **EKS** | `terraform-aws-modules/eks/aws` v21 | K8s v1.33, managed node group, SPOT instances |
| **Subnets** | Auto-calculated via `cidrsubnet()` | `/20` blocks → 4096 IPs each |
| **Provider** | `hashicorp/aws` v6.0 | Region: `us-east-1` |

### Key Design Decisions (Interview Talking Points)

- **Single NAT Gateway**: Cost optimization for dev. Production should use one per AZ for HA.
- **SPOT instances**: 60-90% cost savings. Acceptable for dev workloads.
- **Private subnets for nodes**: Worker nodes and control plane both in private subnets. External access via Gateway API.
- **Subnet tagging**: `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb` tags enable auto-discovery by AWS Load Balancer Controller.
- **Public endpoint**: `endpoint_public_access = true` for kubectl access from outside VPC.

---

## 3. Kubernetes Architecture (Application Layer)

> All manifests live in [kubernetes/](file:///home/ubuntu/Jerney/kubernetes) — namespace: `jerney-ns`

```mermaid
graph TB
    subgraph "Internet"
        USER["🌐 Users"]
    end

    subgraph "EKS Cluster — Namespace: jerney-ns"
        subgraph "Ingress Layer"
            GW["Gateway<br/>(kgateway)<br/>:80 HTTP"]
            HR["HTTPRoute<br/>PathPrefix: /"]
        end

        subgraph "Frontend Tier"
            FD["Deployment: frontend<br/>2 replicas"]
            FS["Service: frontend-service<br/>ClusterIP :8080"]
            FP1["Pod: Nginx + React<br/>:8080"]
            FP2["Pod: Nginx + React<br/>:8080"]
        end

        subgraph "Backend Tier"
            BD["Deployment: backend<br/>2 replicas"]
            BS["Service: backend-service<br/>ClusterIP :5000"]
            BP1["Pod: Node.js/Express<br/>:5000"]
            BP2["Pod: Node.js/Express<br/>:5000"]
        end

        subgraph "Database Tier"
            SS["StatefulSet: db<br/>1 replica"]
            HS["Headless Service: db<br/>ClusterIP: None :5432"]
            DP["Pod: PostgreSQL 17<br/>:5432"]
            PVC["PVC: db-storage<br/>5Gi gp3 (encrypted)"]
        end

        subgraph "Configuration"
            CM["ConfigMap: jerney-configmap"]
            SEC["Secret: jerney-secret"]
        end

        subgraph "Network Policies"
            NP1["NetworkPolicy: db<br/>Ingress only from backend"]
            NP2["NetworkPolicy: backend<br/>Ingress only from frontend"]
        end

        subgraph "Storage"
            SC["StorageClass: jerney-storage-class<br/>ebs.csi.aws.com | gp3 | encrypted"]
        end
    end

    USER --> GW
    GW --> HR
    HR --> FS
    FS --> FP1
    FS --> FP2
    FP1 -->|"/api/* proxy"| BS
    FP2 -->|"/api/* proxy"| BS
    BS --> BP1
    BS --> BP2
    BP1 --> HS
    BP2 --> HS
    HS --> DP
    DP --> PVC
    PVC --> SC
    CM -.->|"envFrom"| BP1
    CM -.->|"envFrom"| BP2
    SEC -.->|"env"| BP1
    SEC -.->|"env"| BP2
    SEC -.->|"env"| DP
    CM -.->|"env"| DP
```

### Kubernetes Resources Breakdown

| # | Resource | File | Details |
|---|---|---|---|
| 1 | **Namespace** | [01-namespace.yml](file:///home/ubuntu/Jerney/kubernetes/01-namespace.yml) | `jerney-ns` with label `app.kubernetes.io/part-of: jerney` |
| 2 | **ConfigMap** | [02-configmap.yml](file:///home/ubuntu/Jerney/kubernetes/02-configmap.yml) | `POSTGRES_DB`, `DB_HOST`, `PORT`, `DB_NAME`, `DB_PORT` |
| 3 | **Secret** | [03-secrets.yml](file:///home/ubuntu/Jerney/kubernetes/03-secrets.yml) | `POSTGRES_USER/PASSWORD`, `DB_USER/PASSWORD` (base64 Opaque) |
| 4 | **Frontend Deployment** | [04-frontend-deployment.yml](file:///home/ubuntu/Jerney/kubernetes/04-frontend-deployment.yml) | 2 replicas, Nginx serving React, `:8080`, non-root (UID 101) |
| 5 | **Backend Deployment** | [05-backend-deployment.yml](file:///home/ubuntu/Jerney/kubernetes/05-backend-deployment.yml) | 2 replicas, Node.js/Express, `:5000`, non-root (UID 1000), readOnlyRootFilesystem |
| 6 | **Frontend Service** | [06-frontend-service.yml](file:///home/ubuntu/Jerney/kubernetes/06-frontend-service.yml) | ClusterIP `:8080` |
| 7 | **Backend Service** | [07-backend-service.yml](file:///home/ubuntu/Jerney/kubernetes/07-backend-service.yml) | ClusterIP `:5000` |
| 8 | **DB StatefulSet** | [08-statefulset.yml](file:///home/ubuntu/Jerney/kubernetes/08-statefulset.yml) | 1 replica, PostgreSQL 17-alpine, `:5432`, PVC 5Gi |
| 9 | **DB Headless Service** | [09-statefulSet-service.yml](file:///home/ubuntu/Jerney/kubernetes/09-statefulSet-service.yml) | `clusterIP: None` — stable DNS: `db-statefulset-0.db.jerney-ns.svc.cluster.local` |
| 10 | **StorageClass** | [10-storageClass.yml](file:///home/ubuntu/Jerney/kubernetes/10-storageClass.yml) | `ebs.csi.aws.com`, gp3, encrypted, Retain, WaitForFirstConsumer |
| 11 | **Gateway** | [11-gateway.yml](file:///home/ubuntu/Jerney/kubernetes/11-gateway.yml) | Gateway API (kgateway), HTTP `:80` |
| 12 | **HTTPRoute** | [12-http-routes.yml](file:///home/ubuntu/Jerney/kubernetes/12-http-routes.yml) | PathPrefix `/` → `frontend-service:8080` |
| 13 | **DB NetworkPolicy** | [13-networkPolicyDB.yml](file:///home/ubuntu/Jerney/kubernetes/13-networkPolicyDB.yml) | DB accepts ingress only from backend pods on `:5432` |
| 14 | **Backend NetworkPolicy** | [14-networkPolicyBackend.yml](file:///home/ubuntu/Jerney/kubernetes/14-networkPolicyBackend.yml) | Backend accepts ingress only from frontend pods on `:5000` |

---

## 4. Network Security & Traffic Flow

```mermaid
graph LR
    subgraph "Allowed Traffic (NetworkPolicies)"
        U["🌐 Internet"] -->|":80 HTTP"| GW["Gateway"]
        GW -->|"PathPrefix /"| FE["Frontend Pods<br/>:8080"]
        FE -->|"Nginx /api/* proxy"| BE["Backend Pods<br/>:5000"]
        BE -->|"pg connection"| DB["Database Pod<br/>:5432"]
    end

    style U fill:#4CAF50,color:#fff
    style GW fill:#2196F3,color:#fff
    style FE fill:#FF9800,color:#fff
    style BE fill:#9C27B0,color:#fff
    style DB fill:#F44336,color:#fff
```

### Network Security Rules

| Policy | Target Pods | Allowed Source | Port | Effect |
|---|---|---|---|---|
| `backend-network-policy` | `backend-deployment` | Only `frontend-deployment` pods | TCP `5000` | **Backend is isolated** — no direct internet access |
| `db-network-policy` | `db-statefulset` | Only `backend-deployment` pods | TCP `5432` | **DB is fully isolated** — only backend can reach it |

> [!IMPORTANT]
> **Interview Key Point**: This implements a **zero-trust, defense-in-depth** networking model. Even if an attacker compromises the frontend pod, they cannot directly reach the database — they must go through the backend, and the backend has `readOnlyRootFilesystem: true`.

---

## 5. CI/CD Pipeline (GitHub Actions)

> Defined in [cicd.yml](file:///home/ubuntu/Jerney/.github/workflows/cicd.yml)

```mermaid
graph LR
    subgraph "Triggers"
        PUSH["git push (any branch)"]
        PR["Pull Request"]
    end

    subgraph "Stage 1: Lint"
        L1["ESLint Backend"]
        L2["ESLint Frontend"]
    end

    subgraph "Stage 2: SCA"
        S1["npm audit Backend"]
        S2["npm audit Frontend"]
    end

    subgraph "Stage 3: Build & Push"
        B1["Docker Build Backend"]
        B2["Docker Build Frontend"]
        GHCR["GHCR Push<br/>+ Provenance<br/>+ SBOM"]
    end

    subgraph "Stage 4: Image Scan"
        T1["Trivy Scan Backend"]
        T2["Trivy Scan Frontend"]
    end

    PUSH --> L1
    PUSH --> L2
    PR --> L1
    PR --> L2
    L1 --> S1
    L2 --> S2
    S1 --> B1
    S2 --> B2
    B1 --> GHCR
    B2 --> GHCR
    B1 --> T1
    B2 --> T2
```

### Pipeline Stages Detail

| Stage | Tool | Purpose | Fail Behavior |
|---|---|---|---|
| **1. Lint** | ESLint | Code quality & style enforcement | `continue-on-error: true` |
| **2. SCA** | `npm audit` | Dependency vulnerability scan (HIGH+) | Warns but continues |
| **3. Build** | Docker Buildx + GHCR | Multi-tag build (SHA, branch, latest), GHA layer caching | Blocks on failure |
| **4. Image Scan** | Trivy | Container CVE scan (CRITICAL, HIGH) | `continue-on-error: true` |

### Docker Image Tags Strategy

```
ghcr.io/pawarhimanshu934/jerney/jerney-frontend:abc1234    # SHA-based (immutable)
ghcr.io/pawarhimanshu934/jerney/jerney-frontend:main       # Branch-based (mutable)
ghcr.io/pawarhimanshu934/jerney/jerney-frontend:latest     # Only on default branch
```

### Supply Chain Security

- **Provenance**: Cryptographic attestation of build origin (who, when, where).
- **SBOM**: Full software bill of materials embedded in image (OS packages + npm deps).
- **GHA Cache**: Bidirectional Docker layer caching via `cache-from/cache-to: type=gha`.

---

## 6. Container Architecture (Docker)

```mermaid
graph TB
    subgraph "Frontend Container"
        subgraph "Build Stage (discarded)"
            FN1["node:20-alpine"]
            FN2["npm ci → vite build"]
        end
        subgraph "Production Stage"
            FN3["nginx:1.30.3-alpine"]
            FN4["/usr/share/nginx/html (React dist)"]
            FN5["Custom nginx.conf<br/>Reverse proxy /api/* → backend:5000"]
            FN6["USER nginx (UID 101)"]
        end
    end

    subgraph "Backend Container"
        subgraph "Build Stage (discarded) "
            BN1["node:20-alpine"]
            BN2["npm ci (deps only)"]
        end
        subgraph "Production Stage "
            BN3["node:20-alpine"]
            BN4["dumb-init (PID 1)"]
            BN5["node src/index.js"]
            BN6["USER appuser (non-root)"]
        end
    end

    subgraph "Database Container"
        DB1["postgres:17-alpine"]
        DB2["PGDATA: /var/lib/postgresql/data/pgdata"]
        DB3["USER postgres (UID 70)"]
    end
```

### Docker Security Hardening

| Practice | Frontend | Backend | Database |
|---|---|---|---|
| **Multi-stage build** | ✅ | ✅ | N/A (official image) |
| **Non-root user** | ✅ `nginx` (101) | ✅ `appuser` (1000) | ✅ `postgres` (70) |
| **Read-only rootfs** | ❌ (Nginx needs cache) | ✅ | ❌ (Postgres needs write) |
| **dumb-init (PID 1)** | ❌ (Nginx is init-safe) | ✅ | ❌ (Postgres is init-safe) |
| **Alpine base** | ✅ | ✅ | ✅ |
| **`allowPrivilegeEscalation: false`** | ✅ | ✅ | ✅ |

---

## 7. Application Data Flow

```mermaid
sequenceDiagram
    actor User
    participant GW as Gateway<br/>:80
    participant Nginx as Frontend Pod<br/>(Nginx :8080)
    participant Express as Backend Pod<br/>(Express :5000)
    participant PG as PostgreSQL Pod<br/>(:5432)
    participant EBS as AWS EBS<br/>(gp3 5Gi)

    User->>GW: HTTP Request
    GW->>Nginx: Route (PathPrefix /)
    
    alt Static Asset (React SPA)
        Nginx-->>User: HTML/JS/CSS
    end
    
    alt API Request (/api/*)
        Nginx->>Express: Reverse Proxy /api/*
        Express->>PG: SQL Query via pg client
        PG->>EBS: Read/Write Data
        EBS-->>PG: Data
        PG-->>Express: Query Result
        Express-->>Nginx: JSON Response
        Nginx-->>User: JSON Response
    end
```

---

## 8. Storage Architecture

```mermaid
graph TB
    subgraph "Kubernetes"
        SS["StatefulSet: db<br/>1 replica"]
        PVC["PVC: db-storage<br/>5Gi, ReadWriteOnce"]
        SC["StorageClass: jerney-storage-class"]
    end

    subgraph "AWS"
        CSI["EBS CSI Driver"]
        EBS["EBS Volume<br/>gp3 | encrypted<br/>Retain policy"]
    end

    SS --> PVC
    PVC --> SC
    SC --> CSI
    CSI --> EBS

    style EBS fill:#FF5722,color:#fff
```

| Setting | Value | Why |
|---|---|---|
| **Provisioner** | `ebs.csi.aws.com` | AWS EBS CSI driver for dynamic provisioning |
| **Type** | `gp3` | Better price-performance than gp2 (3000 IOPS baseline) |
| **Encrypted** | `true` | Data at rest encryption via AWS KMS |
| **ReclaimPolicy** | `Retain` | Prevents accidental data loss on PVC deletion |
| **VolumeBindingMode** | `WaitForFirstConsumer` | Ensures EBS volume is created in the same AZ as the pod |
| **AccessMode** | `ReadWriteOnce` | Single-node attachment (EBS limitation) |

---

## 9. Deployment Modes Summary

The project supports **3 deployment modes**:

```mermaid
graph LR
    subgraph "Mode 1: EC2 (Bare Metal)"
        EC2["Ubuntu EC2"]
        PM2["PM2 Process Manager"]
        NGX["Nginx Reverse Proxy"]
        PGD["PostgreSQL (apt)"]
    end

    subgraph "Mode 2: Docker Compose (Local Dev)"
        DC["docker-compose.yml"]
        FC["Frontend Container"]
        BC["Backend Container"]
        DBC["Postgres Container"]
        VOL["pgdata Volume"]
    end

    subgraph "Mode 3: EKS (Production)"
        TF2["Terraform → VPC + EKS"]
        K8["Kubernetes Manifests"]
        GHCR2["GHCR Images"]
        EBS2["EBS Persistent Storage"]
    end
```

| Mode | Entry Point | Use Case | Orchestration |
|---|---|---|---|
| **EC2 Bare Metal** | [deploy/setup.sh](file:///home/ubuntu/Jerney/deploy/setup.sh) | Quick demo / single server | PM2 + Nginx + PostgreSQL (apt) |
| **Docker Compose** | [docker-compose.yml](file:///home/ubuntu/Jerney/docker-compose.yml) | Local development | Docker Compose (3 services) |
| **EKS (Production)** | [terraform/](file:///home/ubuntu/Jerney/terraform) + [kubernetes/](file:///home/ubuntu/Jerney/kubernetes) | Production / Scalable | Terraform + Kubernetes |

---

## 10. Security Summary (Interview Cheat Sheet)

### At Every Layer

| Layer | Security Controls |
|---|---|
| **CI/CD** | ESLint, npm audit (SCA), Trivy image scanning, Provenance, SBOM |
| **Container** | Multi-stage builds, non-root users, Alpine base, dumb-init, read-only rootfs |
| **Kubernetes** | `runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `automountServiceAccountToken: false` |
| **Networking** | NetworkPolicies (DB ← Backend only, Backend ← Frontend only), ClusterIP services (no NodePort/LB exposure) |
| **Storage** | EBS encryption at rest, Retain reclaim policy |
| **Nginx** | Security headers (X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy), dotfile blocking |
| **Secrets** | K8s Secrets (base64 Opaque), injected via env vars (not mounted files) |

---

## 11. Tech Stack Quick Reference

| Component | Technology | Version |
|---|---|---|
| **Frontend** | React + Vite + Nginx | React 18, Vite 5, Nginx 1.30 |
| **Backend** | Node.js + Express | Node 20, Express 4.21 |
| **Database** | PostgreSQL | 17 (Alpine) |
| **IaC** | Terraform | ≥ 1.2, AWS Provider v6 |
| **Container Runtime** | Docker (multi-stage) | Alpine-based |
| **Orchestration** | AWS EKS (Managed K8s) | v1.33 |
| **CI/CD** | GitHub Actions | Reusable matrix strategy |
| **Registry** | GitHub Container Registry (GHCR) | OCI-compliant |
| **Ingress** | Kubernetes Gateway API (kgateway) | v1 |
| **Security Scanning** | Trivy, ESLint, npm audit | Latest |

---

## 12. Repository Structure Map

```
Jerney/
├── .github/workflows/
│   └── cicd.yml                    # CI/CD Pipeline (Lint → SCA → Build → Scan)
├── backend/
│   ├── Dockerfile                  # Multi-stage: node:20-alpine → dumb-init
│   ├── src/
│   │   ├── index.js                # Express server entry point
│   │   ├── db.js                   # PostgreSQL connection (pg client)
│   │   └── routes/                 # API route handlers
│   └── package.json                # express, pg, cors, dotenv
├── frontend/
│   ├── Dockerfile                  # Multi-stage: node:20-alpine → nginx:1.30-alpine
│   ├── nginx.conf                  # SPA routing + /api/* reverse proxy
│   ├── src/                        # React components
│   └── package.json                # react, react-router-dom, axios
├── terraform/
│   ├── vpc.tf                      # VPC, 3 AZs, public/private subnets, NAT
│   ├── eks.tf                      # EKS cluster, managed node group (SPOT)
│   ├── variable.tf                 # cluster_name, version, region, CIDR
│   ├── output.tf                   # VPC ID, subnets, cluster endpoint
│   └── terraform.tf                # AWS provider v6, Terraform ≥ 1.2
├── kubernetes/
│   ├── 01-namespace.yml            # jerney-ns
│   ├── 02-configmap.yml            # Non-sensitive config
│   ├── 03-secrets.yml              # DB credentials (base64)
│   ├── 04-frontend-deployment.yml  # 2 replicas, Nginx+React
│   ├── 05-backend-deployment.yml   # 2 replicas, Express API
│   ├── 06-frontend-service.yml     # ClusterIP :8080
│   ├── 07-backend-service.yml      # ClusterIP :5000
│   ├── 08-statefulset.yml          # PostgreSQL, PVC, health probes
│   ├── 09-statefulSet-service.yml  # Headless service for DNS
│   ├── 10-storageClass.yml         # EBS CSI, gp3, encrypted
│   ├── 11-gateway.yml              # Gateway API entry point
│   ├── 12-http-routes.yml          # Route to frontend
│   ├── 13-networkPolicyDB.yml      # DB ← Backend only
│   └── 14-networkPolicyBackend.yml # Backend ← Frontend only
├── deploy/
│   ├── setup.sh                    # EC2 bare-metal setup script
│   └── jerney-nginx.conf           # Nginx config for EC2 mode
└── docker-compose.yml              # Local dev (3 services)
```

---

> [!TIP]
> **Interview Pro Tip**: When explaining this architecture, walk through it layer by layer: **Terraform provisions the infra** → **GitHub Actions builds & secures the images** → **Kubernetes orchestrates the workload** → **NetworkPolicies enforce zero-trust** → **StorageClass provides persistent encrypted storage**. This shows you understand the full DevOps lifecycle from code commit to production.
