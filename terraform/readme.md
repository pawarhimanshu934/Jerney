AWS EKS Arch using Terraform

Resource Created :
VPC
EKS

Why VPC is needed?
-> To secure your EKS cluster, using a VPC is best practice. 
Amazon Elastic Kubernetes Service (EKS) is designed to run inside a VPC (Virtual Private Cloud) mainly for network control, security, and integration reasons. Here’s a clear breakdown:

🔒 1. Security & Isolation
A VPC gives you a private network boundary in AWS.
Your Kubernetes worker nodes run on EC2 instances, which must be inside a VPC.
You can control:
Who can access your cluster (via security groups)
Inbound/outbound traffic (via NACLs and routing)
You can keep workloads private (no public internet exposure) if needed.
🌐 2. Networking Control
Kubernetes requires communication between:
Pods ↔ Pods
Pods ↔ Services
Nodes ↔ Control plane
VPC enables:
Custom IP ranges (CIDR blocks)
Subnets (public/private)
Routing policies
EKS uses VPC networking to assign IP addresses directly to pods, which simplifies communication.
🔗 3. Integration with AWS Services

Running EKS inside a VPC allows seamless connection to:

RDS databases
S3 (via VPC endpoints)
ElastiCache
Internal microservices

This means:

No need to expose services publicly
Lower latency and higher security






Fix this using terraform : 
EKS -> EBS csi driver should be automatically installed
IAM -> our current IAM principal doesn't have access to Kubernetes objects on this cluster.
This might be due to the current principal not having an IAM access entry with permissions to access the cluster.