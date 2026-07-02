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
