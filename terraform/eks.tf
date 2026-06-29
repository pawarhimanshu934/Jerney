#EKS Managed Node Group Mode (live)
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
  }

  # Optional: Additional security group rules to add to the cluster security group. This is useful for allowing access to the cluster from other security groups, such as a bastion host or CI/CD system.
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  # Optional
  endpoint_public_access = true

  # Optional: Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # EKS Managed Node Group(s)
  eks_managed_node_groups = {
    jerney-node-group = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]

      min_size     = 1
      max_size     = 1
      desired_size = 1

      capacity_type = "SPOT"
      disk_size     = 30

      labels = {
        "node-group" = "jersey"
      }
    }

    tags = {
      Environment = "dev"
      Terraform   = "true"
    }
  }
}

#keeping worker and controller plane in same private subnets for now, but can be changed to have worker nodes in public subnets if needed.
#using API Gateway to access the cluster from outside the VPC, so no need for public subnets for worker nodes.


#EKS Auto Mode (Preview)
# module "eks" {
#   source  = "terraform-aws-modules/eks/aws"
#   version = "~> 21.0"

#   name               = var.cluster_name
#   kubernetes_version = var.cluster_version

#   # Optional
#   endpoint_public_access = true

#   # Optional: Adds the current caller identity as an administrator via cluster access entry
#   enable_cluster_creator_admin_permissions = true

#   compute_config = {
#     enabled    = true
#     node_pools = ["general-purpose", "system"]
#   }

#   vpc_id                   = module.vpc.vpc_id
#   subnet_ids               = module.vpc.private_subnets
#   control_plane_subnet_ids = module.vpc.private_subnets

#   # Auth mode required for Auto Mode, Controls how access to the cluster is managed.
#   authentication_mode = "API"

#   #Encrypts Kubernetes Secrets using AWS KMS, it encrypt things like DB passwords API keys, Tokens and store encrypted in etcd
#   encryption_config = {
#     resorces = ["secrets"]
#   }

#   #Sends control plane logs to CloudWatch
#   enabled_log_types = [
#     "api",
#     "audit",
#     "authenticator",
#     "controllerManager",
#     "scheduler"
#   ]


#   tags = {
#     Environment = "dev"
#     Terraform   = "true"
#   }
# }


# # | Setup                           | Behavior                                     |
# # | ------------------------------- | -------------------------------------------- |
# # | `["general-purpose"]`           | All workloads share same nodes               |
# # | `["general-purpose", "system"]` | System workloads isolated on dedicated nodes,  |

# # 🟢 general-purpose :
# # Default pool
# # Runs:
# #   Your applications
# #   Deployments
# #   Services
# #   No strict isolation

# # 🔵 system : 
# # Dedicated pool for Kubernetes system components
# # Runs things like:
# #   CoreDNS
# #   kube-proxy
# #   VPC CNI
# #   AWS controllers (ALB controller, etc.)


# # Log	Purpose
# # api	-> All API requests
# # audit ->	Who did what (security critical)
# # authenticator ->	IAM auth activity
# # controllerManager ->	Internal controllers
# # scheduler	-> Pod scheduling decisions

# # Why it matters

# # ✔ Debugging issues
# # ✔ Security auditing
# # ✔ Observability