# VPC
#
# One VPC with three private subnets (one per AZ) for workloads, plus three
# public subnets for NAT gateways and the EKS public endpoint. One NAT per AZ
# in prod; a single NAT would be cheaper but turns one AZ outage into a
# cluster outage. The one-NAT-per-AZ default is overridable for dev/test.

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags that let the AWS Load Balancer Controller discover subnets. Without
  # these the LBC silently picks the wrong set — public subnets for internal
  # LBs or vice versa.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    # Karpenter uses this tag to discover subnets it may place nodes in. The
    # value is arbitrary; the cluster name is the convention.
    "karpenter.sh/discovery" = var.cluster_name
  }
}
