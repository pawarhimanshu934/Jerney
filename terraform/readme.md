AWS EKS Arch using Terraform

Resource Created :
VPC
EKS

Why VPC is needed?
-> To secure your EKS cluster, using a VPC is best practice. 



Fix this using terraform : 
EKS -> EBS csi driver should be automatically installed
IAM -> our current IAM principal doesn't have access to Kubernetes objects on this cluster.
This might be due to the current principal not having an IAM access entry with permissions to access the cluster.