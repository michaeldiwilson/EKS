# External Secrets Operator
#
# ESO pulls secrets from AWS Secrets Manager at runtime and projects them as
# native Kubernetes Secrets. Nothing sensitive touches git.
#
# IRSA role here; the ClusterSecretStore + ExternalSecret manifests under
# `kubernetes/external-secrets/` tell ESO which secrets to pull and how to
# shape them.

# Install the controller.
resource "helm_release" "external_secrets" {
  namespace        = "external-secrets"
  create_namespace = true

  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.10.4"
  wait       = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

# IRSA role that the ClusterSecretStore assumes to call Secrets Manager.
data "aws_iam_policy_document" "eso_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.cluster_name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.eso_trust.json
}

# Deliberately narrow: this role only reads secrets under a per-cluster
# prefix. A broader `secret:*` grant is one of the most common ESO
# misconfigurations and the one that bites hardest in an audit.
data "aws_iam_policy_document" "eso_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:aws:secretsmanager:${var.region}:*:secret:${var.cluster_name}/*"
    ]
  }
}

resource "aws_iam_role_policy" "eso_read" {
  name   = "secrets-read"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_read.json
}

output "external_secrets_role_arn" {
  description = "IRSA role ARN annotated onto the ESO service account."
  value       = aws_iam_role.eso.arn
}
