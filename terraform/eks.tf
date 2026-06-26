module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  # Optional
  endpoint_public_access = true

  # Optional: Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true

  compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Auth mode required for Auto Mode, Controls how access to the cluster is managed.
  authentication_mode = "API"

  #Encrypts Kubernetes Secrets using AWS KMS, it encrypt things like DB passwords API keys, Tokens and store encrypted in etcd
  encryption_config = {
    resorces = ["secrets"]
  }

  #Sends control plane logs to CloudWatch
  enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]


  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}


# | Setup                           | Behavior                                     |
# | ------------------------------- | -------------------------------------------- |
# | `["general-purpose"]`           | All workloads share same nodes               |
# | `["general-purpose", "system"]` | System workloads isolated on dedicated nodes,  |

# 🟢 general-purpose :
# Default pool
# Runs:
#   Your applications
#   Deployments
#   Services
#   No strict isolation

# 🔵 system : 
# Dedicated pool for Kubernetes system components
# Runs things like:
#   CoreDNS
#   kube-proxy
#   VPC CNI
#   AWS controllers (ALB controller, etc.)


# Log	Purpose
# api	-> All API requests
# audit ->	Who did what (security critical)
# authenticator ->	IAM auth activity
# controllerManager ->	Internal controllers
# scheduler	-> Pod scheduling decisions

# Why it matters

# ✔ Debugging issues
# ✔ Security auditing
# ✔ Observability