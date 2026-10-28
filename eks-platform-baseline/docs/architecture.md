# Architecture

```
                       ┌──────────────────────────────┐
                       │        GitHub Actions        │
                       │                              │
                       │  PR → terraform plan comment │
                       │  main → terraform apply      │
                       └──────────────┬───────────────┘
                                      │ OIDC
                                      │ (no stored keys)
                                      ▼
                       ┌──────────────────────────────┐
                       │     AWS IAM Role (CI)        │
                       └──────────────┬───────────────┘
                                      │
                                      ▼
                   ┌─────────────────────────────────────┐
                   │             VPC (10.0.0.0/16)       │
                   │                                     │
                   │    private subnets x3 ─┐            │
                   │                        │            │
                   │                        ▼            │
                   │              ┌──────────────────┐   │
                   │              │   EKS cluster    │   │
                   │              │                  │   │
                   │              │   bootstrap NG   │   │
                   │              │   (small)        │   │
                   │              │                  │   │
                   │              │   ┌───────────┐  │   │
                   │              │   │ Karpenter │  │   │
                   │              │   │ provisions│  │   │
                   │              │   │   nodes   │  │   │
                   │              │   └─────┬─────┘  │   │
                   │              │         ▼        │   │
                   │              │   workload pods  │   │
                   │              │         │        │   │
                   │              │         ▼        │   │
                   │              │   ESO ── IRSA ── │───┼───▶  Secrets Manager
                   │              │                  │   │
                   │              └──────────────────┘   │
                   └─────────────────────────────────────┘
```

## The pieces

**VPC** — one `/16`, three private subnets, three public, one NAT per AZ.
Load Balancer discovery tags on both tiers so the AWS Load Balancer Controller
places LBs correctly without manual config. Karpenter discovery tag
(`karpenter.sh/discovery = <cluster_name>`) on private subnets and the
cluster security group — Karpenter uses that tag to decide where to launch
nodes.

**EKS** — private API endpoint only. Managed add-ons for `coredns`,
`kube-proxy`, `vpc-cni` (prefix delegation on), and the EBS CSI driver.
IRSA enabled. One small managed node group acts as the bootstrap — enough
to run Karpenter and the ESO controller, nothing else. All workload
capacity comes from Karpenter.

**Karpenter** — watches unschedulable pods, consults the `NodePool` policy,
and launches EC2 instances directly. The `NodePool` here allows the `c`/`m`/
`r` families (generation > 5), medium-to-2xlarge, mixed spot + on-demand.
`consolidationPolicy: WhenEmptyOrUnderutilized` — the one setting that
distinguishes a Karpenter cluster that saves money from one that doesn't.

**External Secrets Operator** — ClusterSecretStore configured against AWS
Secrets Manager, authenticated via IRSA. The IRSA role is scoped to
`baseline/*` secrets — not `*` — so a cluster-wide blast radius takes a
Terraform change, not a slip.

**CI** — GitHub Actions, OIDC. One IAM role, one workflow. Plan on PR with
the output as a comment; apply on merge, gated on a GitHub Environment
review so the apply pauses for a human on prod.

## What I'd add next (and in what order)

1. **Monitoring** — `kube-prometheus-stack` via Helm, remote-write to Grafana
   Cloud or a mimir in another cluster. In its own repo so the chart version
   doesn't move in lockstep with the platform.
2. **Ingress** — AWS Load Balancer Controller + a `Gateway` resource. Also
   in a separate repo for the same reason.
3. **Reloader** — restart pods when their mounted secrets change, so ESO
   rotations propagate without a manual roll.
4. **Backup** — Velero against an S3 bucket + a lifecycle rule.

Each is a small, focused addition. Nothing in here needs to grow bigger than
it is now.

## Costs (ballpark)

For a soak with 2× t3.medium bootstrap + ESO + Karpenter running zero
workload nodes: ~$70/mo. Add workload: Karpenter picks the cheapest
instance that satisfies the pods — a steady 2 vCPU / 4 GiB mix typically
lands under $100/mo total.
