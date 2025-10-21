# Appendix — Safe Ephemeral Apply

Use this guide only after every validation rung is green. It creates a temporary sandbox, applies Terraform, and guarantees clean-up.

## 1. Establish Sandbox Accounts
1. Provision dedicated AWS and GCP projects with cost alerts and restrictive IAM roles.
2. Configure short-lived credentials (AWS IAM role + session, GCP Workload Identity) stored in local profiles.
> **Why this step?** Keeps experiments away from production billing and audit logs.
> **STOP-SIGN:** Real cloud spend ahead—seek approval.

## 2. Tagging & TTL Requirements
1. Set mandatory variables before applying:
   ```bash
   export TF_VAR_use_mock=false
   export TF_VAR_environment="sandbox"
   export TF_VAR_owner="$(whoami)"
   export TF_VAR_ttl_hours=4
   ```
2. Policies in `policy/opa/guardrails.tf.rego` will block applies missing `owner`, `environment`, or `ttl_hours` tags/labels.
> **Why this step?** Enables automated cleanup and accountability.

## 3. Run Ephemeral Apply Locally
1. Use a dedicated state file (`terraform.tfstate.sandbox`) stored locally or in temporary backend buckets.
2. Example flow for AWS:
   ```bash
   cd terraform/environments/prod-aws
   terraform init \
     -backend-config=../backend.tfvars \
     -backend-config="key=sandboxes/$(whoami)/terraform.tfstate"
   terraform apply -auto-approve
   ```
3. Repeat for GCP if needed.
> **Why this step?** Spins up a realistic stack long enough for integration tests.

## 4. Automate Destroy with GitHub Actions (Opt-In)
1. Copy `.github/workflows/validate-only.yml` and create `sandbox-destroy.yml` (example snippet):
   ```yaml
   on:
     schedule:
       - cron: "0 */2 * * *"
   jobs:
     destroy:
       runs-on: ubuntu-latest
       if: github.repository == 'your-org/multi-cloud-arlo-demo'
       steps:
         - uses: actions/checkout@v4
         - name: Set up Terraform
           uses: hashicorp/setup-terraform@v3
         - name: Destroy sandbox
           env:
             AWS_PROFILE: sandbox
             GCP_PROJECT: arlo-sandbox
           run: |
             cd terraform/environments/prod-aws
             terraform init -backend-config=../backend.tfvars
             terraform destroy -auto-approve -var use_mock=false -var ttl_hours=4
   ```
2. The workflow must check TTL tags before destroying; OPA policies surface violations as failures.
> **Why this step?** Provides an automated guard against forgotten sandboxes.

## 5. Clean Up Manually If Needed
1. Run destroys locally if the workflow cannot assume your credentials.
2. Delete temporary backend buckets and DynamoDB lock tables once the sandbox is gone.
> **Why this step?** Prevents drift between automation and actual resource usage.

## 6. Resume Mock Mode
1. After the sandbox run, revert environment variables:
   ```bash
   unset TF_VAR_use_mock TF_VAR_environment TF_VAR_owner TF_VAR_ttl_hours
   ```
2. Re-run `make validate:repo` to ensure no files changed unexpectedly.
> **Why this step?** Returns you to the safe, cost-free workflow.
