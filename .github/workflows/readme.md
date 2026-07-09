# GitHub Actions Security Best Practices

This document outlines the security best practices implemented in your GitHub Actions CI/CD pipeline.

---

## 1. SBOM (Software Bill of Materials)

**What it is:**
Think of this like an ingredient list for your Docker image. It tells you:
- What libraries, packages, and dependencies are inside your Docker image
- Their versions
- Where they came from

**Why it matters:**
- Helps find vulnerable components quickly
- Makes your software more transparent and auditable
- Essential for supply chain security

---

## 2. Provenance (Required in Modern DevSecOps)

**What it is:**
This is like a birth certificate of your Docker image. It answers:
- Who built it?
- When was it built?
- What code and tools were used?
- Where is it coming from (Source)?

**Why it matters:**
- Proves the build is trustworthy
- Helps prevent tampering in the build process
- Ensures build integrity and traceability

---

## 3. Image Cosigning

**What it is:**
This is like digitally signing your Docker image before shipping it. When you build a Docker container image:
- You attach a cryptographic signature to it
- Others can verify that signature before using it

**Why it matters:**
- Ensures the image hasn't been modified
- Confirms it came from a trusted source
- Prevents unauthorized image usage

---

## 4. Concurrency

**What it is:**
This controls how many workflows or jobs run at the same time.

**Example:**
- Prevent multiple deployments running simultaneously
- Cancel older runs when a new one starts

**Why it matters:**
- Avoids conflicts (like two deployments at once)
- Saves resources and keeps pipelines clean
- Prevents race conditions

---

## 5. Checkov

**What it is:**
Checkov is a tool used to scan Infrastructure as Code (IaC), container images, and open-source packages for security and compliance misconfigurations.

### Configuration Options

#### `soft_fail` Setting

Controls how Checkov behaves when it finds issues:

**soft_fail: false** (Strict Mode)
```yaml
soft_fail: false
```
- ❌ Step fails if ANY policy fails
- ❌ Pipeline fails
- ❌ Deployment blocked

✔️ **Use this for:**
- Terraform configurations
- Production environments
- Security-critical infrastructure

**soft_fail: true** (Warning Mode)
```yaml
soft_fail: true
```
- ⚠️ Issues are shown
- ✅ Pipeline CONTINUES

✔️ **Use this for:**
- Kubernetes manifests
- Early-stage projects
- When some checks are not applicable

#### `skip_check` Setting

Tells Checkov: "Don't flag these specific security checks"

```yaml
skip_check: CKV_AWS_39,CKV_AWS_58
```

Example:
- `CKV_AWS_39` → EKS public endpoint
- `CKV_AWS_58` → AWS-related security rule

**Important:** Skipping = you accept the risk

**Understanding Check IDs:**
Checkov has a built-in library of security rules, each with a unique ID format:
```
CKV_<PROVIDER>_<NUMBER>
```

#### `output_format` Setting

Controls how scan results are displayed in logs and reports.

---

## 6. Docker Build Caching

### Cache Strategy

- `cache-from` → Use old cache
- `cache-to` → Save new cache

**Note:** This is bi-directional caching for optimal build performance.

---

## Understanding Docker Image Digests

### What is a Digest?

When Docker builds an image, it takes the entire content of that image (all layers, config, everything) and runs it through a hash function (SHA-256). The output is a fixed-length string like:

```
sha256:a1b2c3d4e5f6...
```

This is the digest. Think of it like a fingerprint.

### Tag vs. Digest

| Aspect | Tag | Digest |
|--------|-----|--------|
| Example | `:latest`, `:himanshu`, `:main` | `@sha256:a1b2c3d4e5f6...` |
| Behavior | Mutable - can be reassigned | Immutable - derived from content |
| Mutability | You can peel it off and stick it on a different box later | If even one byte of the image changes, the digest changes completely |

**Real-world example:**
- `ghcr.io/repo/jerney-backend:himanshu` might point to a different image next week if someone rebuilds and pushes with the same tag
- `ghcr.io/repo/jerney-backend@sha256:a1b2c3d4...` will always refer to the exact same image

---

## Handling Matrix Jobs and Digest Outputs

### The Problem with Matrix Jobs

In non-matrix jobs, this pattern works fine:

```yaml
build:
  outputs:
    digest: ${{ steps.build.outputs.digest }}

cosign:
  needs: build
  run: echo ${{ needs.build.outputs.digest }}
```

However, your build job uses `strategy: matrix: component: [backend, frontend]`. This means:
- `build` actually runs twice as two separate parallel job instances
  - One for `backend`
  - One for `frontend`
- GitHub Actions doesn't merge these into a list
- `needs.build.outputs.digest` in your `cosign` job could end up being the frontend digest for both components

This causes incorrect digest references.

### Solution: Use Artifacts

Upload each digest to a separate artifact file:

1. **Write each digest to a file** → Upload as a matrix-scoped artifact
   - Name artifacts: `digest-backend` and `digest-frontend`
   - Use `matrix.component` in the artifact name

2. **Download in cosign job** → Use the matching component matrix value
   - This keeps the two digest values physically separate
   - Each digest is tagged by which component it belongs to

**Alternative approach:**
Give each matrix job's output a unique name using `matrix.component` baked into the job ID, but GitHub Actions doesn't allow dynamic job IDs, so the artifact approach is preferred.

---

## Summary

These security practices ensure:
- ✅ Supply chain integrity
- ✅ Build process transparency
- ✅ Artifact authentication
- ✅ Resource efficiency
- ✅ Security compliance
