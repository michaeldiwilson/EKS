# EKS
#
# A single managed node group — just large enough to bootstrap the control
# plane add-ons (CoreDNS, Karpenter itself). All real workload capacity comes
# from Karpenter below, so this group stays small and cheap.
#
# Private endpoint only. kubectl access goes through the account's SSO path,
# not a public API server with an IP allowlist.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  # IRSA is non-negotiable. Every workload role in this repo expects it.
  enable_irsa = true

  # Addons managed by EKS. vpc-cni is set to prefix-mode so each ENI
  # advertises /28 of IPs instead of one per ENI — the classic fix for pod-IP
  # exhaustion before you reach for secondary CIDRs.
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # Bootstrap node group. Three t3.medium nodes is plenty for the add-ons;
  # Karpenter does the rest.
  eks_managed_node_groups = {
    bootstrap = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      labels = {
        role = "bootstrap"
      }

      # Taint keeps workloads off the bootstrap nodes once Karpenter is up —
      # Karpenter-provisioned nodes don't carry this taint.
      taints = {
        bootstrap = {
          key    = "role"
          value  = "bootstrap"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # The tag Karpenter uses to find the cluster's security group when
  # launching new nodes.
  tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}
