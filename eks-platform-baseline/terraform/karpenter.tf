# Karpenter
#
# Karpenter watches for unschedulable pods and provisions nodes directly via
# EC2 Fleet. Shape and policy are expressed in the NodePool + EC2NodeClass
# manifests under `kubernetes/karpenter/`; this file sets up the IAM and the
# controller install.

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24"

  cluster_name          = module.eks.cluster_name
  enable_v1_permissions = true

  # Reuse the EKS node IAM role for Karpenter-provisioned nodes. The module
  # takes care of registering it in aws-auth.
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.cluster_name}-karpenter-node"

  # The controller runs on the bootstrap node group (via Helm below). Give it
  # IRSA for the EC2 Fleet + spot interruption queue permissions.
  create_pod_identity_association = true
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.0.6"
  wait       = true

  values = [
    yamlencode({
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.karpenter.iam_role_arn
        }
      }
      # Pin controller onto the bootstrap group so it can bring up its own
      # fleet. Without the toleration it'd never schedule — the bootstrap
      # group carries a NoSchedule taint.
      tolerations = [{
        key      = "role"
        operator = "Equal"
        value    = "bootstrap"
        effect   = "NoSchedule"
      }]
      nodeSelector = {
        role = "bootstrap"
      }
    })
  ]
}
