# ADR 001: Karpenter over managed node groups for workload capacity

**Status**: accepted
**Date**: 2026-10-28

## Context

EKS gives two paths to add node capacity:

1. **Managed node groups (MNG)** — AWS-managed ASG per instance type, scaled
   by Cluster Autoscaler or by hand. Simple to understand, slow to react,
   locks you into pre-chosen instance types.

2. **Karpenter** — watches unschedulable pods and launches instances
   directly through EC2 Fleet, within a policy (`NodePool`) you define. No
   ASG involved.

## Decision

Karpenter for all workload capacity. One small MNG stays, but only for the
cluster add-ons that have to exist before Karpenter does (CoreDNS,
kube-proxy, Karpenter itself, ESO).

## Why

- **Instance choice follows pod shape.** Karpenter picks the cheapest
  instance that satisfies a pending pod — you don't have to curate an ASG
  per shape.
- **Scaling in seconds, not minutes.** No ASG warm-pool trickery; Karpenter
  issues RunInstances directly.
- **Spot handled correctly.** Karpenter rebalances fleet across capacity
  pools, consumes the interruption queue, and drains cleanly on reclaim.
- **Upgrades fall out of consolidation.** `expireAfter: 720h` on the
  NodePool rolls the whole fleet weekly; node AMI version drift stops being
  something you have to think about.

## The gotcha

`consolidationPolicy` has two values that look similar and behave very
differently.

- `WhenEmpty` — only consolidates empty nodes. Underutilised nodes stay up
  forever. The default-looking choice that quietly costs you money.
- `WhenEmptyOrUnderutilized` — the one you actually want. Repacks fewer,
  busier nodes.

We default to `WhenEmptyOrUnderutilized` with a 20% disruption budget to
keep churn bounded. For latency-sensitive workloads, a `do-not-disrupt`
annotation on specific deployments gets you per-workload opt-out without
changing the policy.

## When I'd flip

If workloads become so homogeneous that pre-provisioning a single-instance-
type ASG wins on scheduling latency, go back to MNG. In practice I've
never seen that case stick.
