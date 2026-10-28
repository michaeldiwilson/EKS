# GitHub Actions OIDC
#
# One IAM role, assumable by a specific GitHub repo via OIDC, that
# Terraform runs under in CI. No stored AWS keys in GitHub secrets.
#
# The provider thumbprint is intentionally not pinned — AWS now accepts any
# valid cert for the GitHub OIDC provider URL, and pinning it means a
# certificate rotation at GitHub breaks CI silently.
#
# NOTE: on new repos created after August 2026, GitHub injects an immutable
# subject (`repo:<owner>@<id>/<repo>@<id>:...`). The condition below allows
# both the legacy and immutable forms so a repo migration doesn't lock CI
# out.

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.oidc_github_repo}:*",
        "repo:${split("/", var.oidc_github_repo)[0]}@*/${split("/", var.oidc_github_repo)[1]}@*:*",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.cluster_name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json

  description = "Terraform CI role. Assumed by GitHub Actions via OIDC."
}

# Deliberately broad for now — tighten per-workload as the stack grows.
# AdministratorAccess is fine for a solo-dev portfolio repo; a real
# multi-team setup would split plan (ReadOnly) and apply (scoped writer).
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "github_actions_role_arn" {
  description = "ARN to put in the GitHub Actions workflow's `role-to-assume`."
  value       = aws_iam_role.github_actions.arn
}
