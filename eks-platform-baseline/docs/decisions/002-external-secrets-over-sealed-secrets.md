# ADR 002: External Secrets Operator over sealed-secrets / SOPS

**Status**: accepted
**Date**: 2026-10-28

## Context

Secrets have to live somewhere. The three mainstream options:

1. **sealed-secrets** — encrypt a Secret with a cluster-held keypair, commit
   the ciphertext. One-way: only the cluster can decrypt.
2. **SOPS + git** — encrypt secret values in YAML with KMS, commit the
   ciphertext. Developers decrypt locally via their IAM identity.
3. **External Secrets Operator (ESO)** — don't put secrets in git at all.
   Pull from AWS Secrets Manager (or Vault, GCP Secret Manager, etc.) at
   runtime and project as a native k8s Secret.

## Decision

ESO against AWS Secrets Manager.

## Why

- **AWS already runs a secrets backend.** Secrets Manager rotation, access
  logging, IAM, and audit trails are already working. Adding sealed-secrets
  or SOPS is reimplementing a subset of that in git.
- **Rotation stays close to the backend.** With sealed-secrets, rotating a
  secret means a commit, PR, review, merge, and deploy. With ESO, rotate
  in Secrets Manager and ESO picks it up on `refreshInterval`.
- **Nothing sensitive in git.** Ever. Not even ciphertext. One less thing
  to worry about on a repo leak.
- **IRSA for access, not a cluster-wide keypair.** sealed-secrets's single
  cluster keypair is a cluster-wide blast radius; ESO's IRSA role is
  per-namespace (or per-cluster, as narrow as you make it).

## The gotcha

ESO caches the resolved Secrets Manager secret ARN by name. If you create a
`ClusterSecretStore` pointing at `prod/myapp`, ESO caches the full ARN —
including the random 6-char suffix AWS appends. If the secret is later
deleted and recreated (new suffix), ESO keeps the old ARN and silently
serves the stale value, forever, with no error.

Guards:
- Prefer `remoteRef.key` referring to the **secret name**, not the full
  ARN. The ESO AWS provider resolves the name every refresh, which avoids
  the cache.
- Monitor `externalsecret_sync_calls_error` — a sudden drop in refresh
  activity on a specific store is the leading signal.
- If a secret has to be recreated, destroy + recreate the matching
  `ExternalSecret` too.

## When I'd flip

Air-gapped clusters with no path to a secrets backend: sealed-secrets
wins. A sufficiently small team that doesn't have a secrets backend at
all: SOPS. Neither is a config this repo is likely to grow into.
