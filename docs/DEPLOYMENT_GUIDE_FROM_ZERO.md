# Multi-Cloud Arlo Deployment From Zero

## 1. Know What You Are Deploying
1. Review the high-level architecture:
   - AWS is the live region with Route53 health checks, EKS, and DynamoDB global tables.
   - GCP stays warm using Cloud DNS, GKE Autopilot, and DynamoDB global table replicas.
   - Argo CD applies `kubernetes/overlays/{aws,gcp}` while Atlantis manages Terraform PR workflows.
   - Monitoring ships Prometheus federation and Grafana dashboards from `monitoring/`.
   - Operations tooling includes `scripts/simulate_failover.sh`, `tests/smoke.sh`, and `tests/dns_check.py`.
> **Why this step?** Team members share a mental model before touching infra, reducing surprises when validating.
> **STOP-SIGN:** No cloud cost incurred yet.

## 2. Prepare Local Prerequisites
1. Install required tooling (tested versions): Terraform 1.6+, kubectl 1.28+, helm 3.12+, kustomize 5.1+, awscli 2.13+, gcloud 445+, docker 24+, make 4+, pre-commit 3+, infracost 0.10+, tflint 0.47+, tfsec 1.28+, checkov 3.0+, conftest 0.45+, kubeconform 0.6+.
2. Recommended one-liners (adjust for your package manager):
   ```bash
   brew install terraform kubectl helm awscli google-cloud-sdk pre-commit kind infracost tflint tfsec checkov conftest kubeconform
   pipx install pre-commit checkov
   ```
3. Configure AWS/GCP CLIs with profiles that **do not** have default credentials loaded; the validation ladder is credential-free until the optional sandbox.
> **Why this step?** Aligning on versions avoids drift; keeping credentials detached stops accidental applies.
> **STOP-SIGN:** No cloud cost incurred yet.

## 3. Embrace the Safety Model
1. Treat cloud spend as a production incident. We default to LocalStack, mock variables, and KinD.
2. Provider auth and remote backends stay off until the final optional rung.
3. Terraform modules expose `var.use_mock` (default `true` for local flows) and use patterns such as:
   ```hcl
   resource "aws_route53_record" "primary" {
     count = var.use_mock ? 0 : 1
     # real record omitted during local plans
   }

   output "mock_global_lb_hostname" {
     value = var.use_mock ? "mock-global.arlo-resilience.local" : aws_route53_record.primary.fqdn
   }
   ```
4. For DynamoDB and multi-region DNS, mirror the approach:
   ```hcl
   module "global_lb" {
     source   = "../modules/global-lb"
     use_mock = var.use_mock
   }

   module "db_global" {
     source   = "../modules/db-global"
     use_mock = var.use_mock
   }
   ```
> **Why this step?** Reinforces a contract: anything run locally returns mock outputs, yet keeps downstream modules flowing.
> **STOP-SIGN:** No cloud cost incurred yet.

## 4. Climb the Validation Ladder
Run each rung from repository root; every command is idempotent.

### Rung 0 — Repo Hygiene
1. ```bash
   make validate:repo
   ```
2. The target runs pre-commit checks (fmt, lint, markdown, shell).
> **Why this step?** Keeps the repo tidy and blocks style regressions long before infra work.
> **STOP-SIGN:** No cloud cost incurred yet.

### Rung 1 — Terraform Static Analysis
1. ```bash
   make validate:tf:static
   ```
2. Executes Terraform fmt-check, tflint, tfsec (soft fail), checkov, plus `terraform validate` using local backends.
> **Why this step?** Catches syntax and provider drift without touching any cloud APIs.
> **STOP-SIGN:** No cloud cost incurred yet.

### Rung 2 — Policy as Code
1. ```bash
   make validate:tf:policy
   ```
2. Generates throw-away plans with `TF_VAR_use_mock=true` and runs OPA/Conftest rules under `policy/opa/`.
> **Why this step?** Enforces enterprise guardrails (cost ceilings, tagging, region allowlists) before human review.
> **STOP-SIGN:** No cloud cost incurred yet.

### Rung 3 — Local Cloud Planning
1. ```bash
   make validate:tf:plan-local
   ```
2. Produces `plan.out` and `plan.json` in each `terraform/environments/*` using `-backend=false -refresh=false`.
> **Why this step?** Gives engineers the exact changeset for peer review without remote backends or credentials.
> **STOP-SIGN:** No cloud cost incurred yet.

### Rung 4 — Cost Estimation
1. ```bash
   make validate:cost MAX_MONTHLY_DELTA=75
   ```
2. Runs Infracost against `plan.json` and fails if delta exceeds `MAX_MONTHLY_DELTA` (USD/month).
> **Why this step?** Quantifies spend before approvals and tags regressions early.
> **STOP-SIGN:** No cloud cost incurred yet.

### Rung 5 — Local Kubernetes Validation
1. Ensure `docker compose -f tools/local/docker-compose.local.yml up -d kind-bootstrap` has run once (see Section 5).
2. ```bash
   make validate:k8s:local
   ```
3. Kustomize renders overlays, kubeconform validates schemas, and KinD performs server dry-run and `kubectl diff`.
> **Why this step?** Verifies manifests, Argo CD values, and External Secrets wiring using a fake SecretStore.
> **STOP-SIGN:** No cloud cost incurred yet.

### Rung 6 — Offline Smoke Tests
1. ```bash
   make validate:smoke:offline
   ```
2. Spins KinD + CoreDNS stubs, exposes `arlo-demo-app`, and reuses `tests/smoke.sh` with `LOCAL_MODE=1` so HTTPS defaults to localhost certificates.
> **Why this step?** Exercises service health, DNS, and fail-over logic entirely locally.
> **STOP-SIGN:** No cloud cost incurred yet.

### Rung 7 — Optional Ephemeral Sandbox
1. Refer to [`docs/APPENDIX_SAFE_APPLY.md`](APPENDIX_SAFE_APPLY.md).
2. Requires opt-in tags (`owner`, `environment`, `ttl_hours`) and auto-destroy GitHub workflow.
> **Why this step?** Provides a tightly-scoped real cloud rehearsal without risking runaway cost.
> **STOP-SIGN:** Explicitly opt-in; costs money.

## 5. Local Emulation Prerequisites
1. Start the local platform (LocalStack, DynamoDB Local, KinD bootstrap, CoreDNS) with:
   ```bash
   docker compose -f tools/local/docker-compose.local.yml up -d
   tools/local/kind-setup.sh
   ```
2. Inspect [`docs/LOCAL_EMULATION.md`](LOCAL_EMULATION.md) for details about fake SecretStores, DNS overrides, and traffic routing.
> **Why this step?** Guarantees local infra parity so the validation ladder passes consistently.
> **STOP-SIGN:** Docker resources only; still no cloud billing.

## 6. Optional Real Deployment (Post-Validation)
1. Double-check every rung is green. Commit `plan.json` to artifacts; share cost output with stakeholders.
2. Export credentials explicitly per environment (example uses temporary AWS session and GCP Application Default Credentials).
3. AWS deployment:
   ```bash
   cd terraform/environments/prod-aws
   terraform init -backend-config=../backend.tfvars
   terraform plan
   terraform apply
   ```
4. GCP deployment:
   ```bash
   cd ../prod-gcp
   terraform init -backend-config=../backend.tfvars
   terraform apply
   ```
5. Run `tests/smoke.sh` and `tests/dns_check.py` against the real DNS name, then trigger `scripts/simulate_failover.sh` for a supervised warm fail-over.
> **Why this step?** Keeps production changes deliberate and audited behind validation artifacts.
> **STOP-SIGN:** You are now in billable territory—coordinate approvals.

## 7. Next Steps
1. Set up `.github/workflows/validate-only.yml` in your fork to keep PRs on the validation ladder.
2. Add the new `tools/make/Makefile.validate` to your root Makefile include path (see README update).
3. Encourage teammates to contribute additional OPA guardrails as requirements evolve.
> **Why this step?** Institutionalises the safety model and prevents drift from the agreed guardrails.
> **STOP-SIGN:** Still free—only automation config changes.
