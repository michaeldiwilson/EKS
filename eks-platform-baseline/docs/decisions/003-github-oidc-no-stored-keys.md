# ADR 003: GitHub OIDC, no stored AWS keys

**Status**: accepted
**Date**: 2026-10-28

## Context

Two ways to let GitHub Actions call AWS:

1. **Access key + secret in GitHub Secrets.** Long-lived credentials sitting
   in a secrets store; rotation is a chore nobody does on time.
2. **OIDC.** GitHub signs a short-lived JWT for the workflow run; AWS trusts
   that JWT via an IAM OIDC provider; the workflow assumes a role. No
   long-lived credential anywhere.

## Decision

OIDC. One IAM role, trust policy scoped to this specific repo.

## Why

- **No credential to rotate.** The JWT is minted per-run.
- **No credential to leak.** There's nothing in GitHub Secrets to leak.
- **Scope is in the trust policy, not in the secret.** You can tighten
  per-branch, per-environment, per-workflow in one place that a reviewer
  can see.

## The gotcha

GitHub introduced an immutable repo subject in August 2026 for new repos.
The old subject form was:

```
repo:owner/repo:ref:refs/heads/main
```

The new form, for repos created after the change, is:

```
repo:owner@<ownerID>/repo@<repoID>:ref:refs/heads/main
```

A trust policy with `StringEquals` on `repo:owner/repo:*` locks any new
repo out — silently, because the error is on the AWS side at AssumeRole,
not on GitHub's.

Guard: `StringLike` matching both forms, as `terraform/github-oidc.tf`
does. The two patterns are:

```
repo:owner/repo:*
repo:owner@*/repo@*:*
```

(The `@*` wildcards cover whatever numeric id GitHub picked.)

## When I'd flip

Never. OIDC is a strict upgrade over stored keys for any CI pattern.
