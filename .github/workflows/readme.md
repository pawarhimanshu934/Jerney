Security best practices implemented on your github action pipeline.

1) SBOM (Software Bill of Materials)

Think of this like an ingredient list for your Docker image. 

It tells you:

What libraries, packages, and dependencies are inside your Docker image
Their versions
Where they came from

Why it matters:

Helps find vulnerable components quickly
Makes your software more transparent and auditable

2) Provenance ( Required in modern DevSecOps )

This is like birth certificate of your Docker image.

It answers:

Who built it?
When was it built?
What code and tools were used?
Where it is comming from? Source? 

Why it matters:

Proves the build is trustworthy
Helps prevent tampering in the build process

3) Image Cosigning

This is like digitally signing a your Docker image before shipping it.

When you build a docker container image:

You attach a cryptographic signature to it
Others can verify that signature before using it

Why it matters:

Ensures the image hasn’t been modified
Confirms it came from a trusted source

4) Concurrency

This controls how many workflows or jobs run at the same time.

Example:

You can prevent multiple deployments running simultaneously
Or cancel older runs when a new one starts

Why it matters:

Avoids conflicts (like two deployments at once)
Saves resources and keeps pipelines clean

5) Checkov
Checkov is a tool used to scan Infrastructure as Code (IaC), container images, and open-source packages for security and compliance misconfigurations.

<!-- # soft_fail : it controls Checkov on breaking your CI pipeline when it finds issues. If true it wont break, if false then there will be strict scanning.

# soft_fail: false

# 👉 If ANY policy fails:

# ❌ Step fails
# ❌ Pipeline fails
# ❌ Deployment blocked

# ✔️ Use this for:

# Terraform (in your case)
# Production environments
# Security-critical infra


# soft_fail: true

# 👉 If issues are found:

# ⚠️ Issues are shown
# ✅ Pipeline CONTINUES

# ✔️ Use this for:

# Kubernetes manifests (like you did)
# Early-stage projects
# When some checks are not applicable



# skip_check -> Tells Checkov: “Don’t flag these specific security checks” 
# skip_check: CKV_AWS_39,CKV_AWS_58

# You are skipping:
# CKV_AWS_39 → EKS public endpoint
# CKV_AWS_58 → Another AWS-related security rule

# Skipping = you accept the risk

# CKV_AWS_39 -> It’s a policy ID defined by Checkov. Checkov has a huge built-in library of security rules, and each rule gets a unique ID like:
# CKV_<PROVIDER>_<NUMBER>


# output_format — How results are displayed

# ✅ What it does

# Controls how scan results are formatted. -->

6) 
<!-- # cache-from → use old cache
# cache-to   → save new cache

# 👉 This is bi-directional caching -->



Notes : 

What is a digest, really?
When Docker builds an image, it takes the entire content of that image (all layers, config, everything) and runs it through a hash function (SHA-256). The output is a fixed-length string like:
sha256:a1b2c3d4e5f6...
This is the digest. Think of it like a fingerprint:

Tag (e.g. :latest, :himanshu, :main) = a label you stick on a box. You can peel it off and stick it on a different box later. Mutable.
Digest = the box's actual fingerprint, derived from what's physically inside it. If even one byte of the image changes, the digest changes completely. Immutable.

So ghcr.io/repo/jerney-backend:himanshu might point to a different image next week if someone rebuilds and pushes with the same tag. But ghcr.io/repo/jerney-backend@sha256:a1b2c3d4... will always refer to that exact image, forever — that's why signing by digest is the trustworthy way to do it.

Why can't you just use it "directly" — why not needs.build.outputs.digest?
In a non-matrix job, this pattern works totally fine:

build:
  outputs:
    digest: ${{ steps.build.outputs.digest }}
cosign:
  needs: build
  run: echo ${{ needs.build.outputs.digest }}

  The problem is your build job uses strategy: matrix: component: [backend, frontend]. That means build actually runs twice — as two separate parallel job instances, one for backend, one for frontend. Each instance tries to set the same output name (digest).
GitHub Actions doesn't merge these into a list. It just lets the last matrix job to finish win — so needs.build.outputs.digest in your cosign job could end up being the frontend digest for both the backend and frontend signing steps, depending on timing. That's a race condition, and it would silently sign the wrong image. This is a known limitation of GitHub Actions matrix jobs, not a mistake in how you wrote it.
So why artifacts?
Uploading a file as an artifact named digest-backend and digest-frontend (using matrix.component in the artifact name) keeps the two values physically separate, tagged by which component they belong to. Then when the cosign job also runs as a matrix over [backend, frontend], each run downloads only the artifact matching its own matrix.component — so backend always gets backend's digest, frontend always gets frontend's. No race condition, no guessing.
There is a simpler alternative if you want to avoid artifacts entirely: give each matrix job's output a unique name using matrix.component baked into the job id — but GitHub Actions doesn't let you dynamically name outputs per matrix value either, so in practice, artifacts (or writing to a shared file/cache keyed by component) are the standard workaround people use for "pass a per-matrix-value value to a downstream job."


Solution : write each digest to a file → upload as a matrix-scoped artifact → download it in the cosign job using the matching component matrix value.

