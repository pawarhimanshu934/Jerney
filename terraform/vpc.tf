# Using DataSource block to fetch all available AZs in the current region
data "aws_availability_zones" "available" {
  state = "available"

  # Optional: Exclude Local Zones and Wavelength Zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.cluster_name}-vpc"
  cidr = var.cidr_block

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.cidr_block, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.cidr_block, 4, k + 3)]

  enable_nat_gateway = true
  single_nat_gateway = true # Cost-saving for dev; use one per AZ for prod

  #public-facing load balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  #internal-only load balancers
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  map_public_ip_on_launch = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}


# Without these tags:

# Kubernetes (via the AWS cloud provider or AWS Load Balancer Controller) cannot automatically discover subnets
# You would need to manually specify subnet IDs every time you create a LoadBalancer service, which is error-prone and less scalable
# With these tags:  
# Kubernetes can automatically discover which subnets to use for internet-facing and internal load balancers, simplifying the deployment of services and improving scalability.

#when you create a service of type loadBalancer, AWS EKS creates a load balancer resource and that loadBalancer is attached to public subnet



# vpc_cidr = 10.0.0.0/16 
# private_subnets = [ for k, v in local.azs : cidrsubnet(var.cidr_block,4,k)] 
# public_subnets = [ for k, v in local.azs : cidrsubnet(var.cidr_block,8,k)] 

# => 
# there will be total 16(2^4) private subnets holding 4096(16-4 = 2^12) IPs. 
#there will be total 256(2^8) public subnets holding 256() IPs

# But here’s the important catch

# Your loop:

# [ for k, v in local.azs : ... ]

# This means:

# 👉 You only create as many subnets as there are AZs, not all possible ones.

# Example

# If:

# local.azs = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

# Then:

# k = 0,1,2
# You create:
# 3 private subnets (not 16)
# 3 public subnets (not 256)
# Final answer
# ✅ Subnet sizes are correct
# ❌ Total number of subnets is not 16 and 256 in practice, only len(local.azs)