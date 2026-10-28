# eks-platform-baseline

A production-shaped AWS EKS platform in Terraform, with Karpenter for node
autoscaling and External Secrets Operator (ESO) for AWS Secrets Manager →
Kubernetes secret sync, deployed by a GitHub Actions pipeline that uses OIDC
(no long-lived AWS keys).

This is a working reference, not a toy. Everything in it is a pattern I've
used to run multi-environment platforms at scale. It stands on its own: clone
it, point it at your own AWS account, and you have a working cluster.

## What it demonstrates

- **Terraform at platform scale** — module composition, remote state,
  per-environment inputs, no hidden drift between what you write and what runs.
- **EKS without the sharp edges** — IRSA baked in from the start, VPC CNI
  configured to avoid the pod-IP exhaustion trap, Karpenter on the control
  plane instead of a managed node group you have to babysit.
- **Secrets without secrets in git** — ESO pulls from AWS Secrets Manager at
  runtime; nothing sensitive ever touches the repo or the cluster manifests.
- **CI/CD without stored credentials** — GitHub Actions assumes an IAM role
  via OIDC, scoped to this repo. Plan on PR; apply on merge to main. The
  apply job is gated on the plan comment, not on a timer.
- **Documentation that would survive a handover** — architecture.md explains
  what and why; `docs/decisions/` captures the trade-offs behind each choice.

## Layout

```
terraform/           # VPC, EKS, Karpenter, ESO IRSA, outputs
kubernetes/
  karpenter/         # NodePool + EC2NodeClass (what Karpenter actually schedules against)
  external-secrets/  # ClusterSecretStore + a sample ExternalSecret
  sample-app/        # A tiny app that consumes the ExternalSecret end-to-end
.github/workflows/   # OIDC-authenticated plan + apply pipeline
docs/
  architecture.md    # One diagram, one page of prose
  decisions/         # Short ADRs for the non-obvious choices
```

## Quick start

Prereqs: an AWS account you don't mind spending ~$3/day in during a soak,
Terraform ≥1.6, `kubectl`, `awscli`, and a GitHub repo you can set OIDC on.

```sh
# 1. Set up remote state + the GitHub OIDC role (one-off, click-ops or a
#    second Terraform workspace — kept out of this repo on purpose).
# 2. Point terraform/variables.tf at your region + state bucket.
# 3. Open a PR with any change. The pipeline posts a plan.
# 4. Merge. The pipeline applies.
# 5. aws eks update-kubeconfig --name baseline && kubectl apply -f kubernetes/
```

Full walkthrough: [docs/architecture.md](docs/architecture.md).

## Why this shape?

Every choice in here is the one I'd make again. The short version lives in
`docs/decisions/`:

- **Karpenter over managed node groups** — faster scaling, cleaner upgrades,
  no instance-type lock-in. The ADR explains the one gotcha (consolidation on
  spot capacity).
- **VPC CNI with secondary CIDR, not Cilium** — ENI-per-pod is the AWS-native
  path; Cilium is great but a bigger operational surface than most teams need
  on day one. The ADR covers when I'd flip.
- **ESO over sealed-secrets / SOPS** — sync from a secrets backend you
  already run, don't reimplement one in git. The ADR covers the silent-failure
  mode to guard against (stale secret ARN caching).
- **OIDC, not stored IAM keys in GitHub** — zero long-lived credentials.
  The ADR covers the one thing that bit me (immutable `sub` on new GitHub
  repos).

## What's deliberately NOT in here

- A service mesh. Istio/Linkerd is a Week 6 decision, not a Week 1 one.
- Multi-cluster federation. The platform scales vertically a long way before
  it needs to.
- A monitoring stack. kube-prometheus-stack belongs in its own repo so you
  can version it independently from the cluster.

Each of those is a separate repo I'd build the same way.

## License

MIT — do what you like with it.
