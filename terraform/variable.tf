variable "cluster_name" {
  description = "Name of EKS Cluster"
  type        = string
  default     = "Jerney"
}

variable "cluster_version" {
  description = "Version of EKS Cluster"
  type        = string
  default     = "1.33"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cidr_block" {
  description = "Cidr range for VPC"
  type        = string
  default     = "10.0.0.0/16"
}