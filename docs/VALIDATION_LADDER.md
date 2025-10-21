# Validation Ladder Reference

Each rung builds confidence without touching production until the final optional stage. Every command runs from the repository root unless noted otherwise.

## Rung 0 — Repo Hygiene (`make validate:repo`)
1. Runs `pre-commit run --all-files` with formatters for Terraform, Markdown, YAML, shell, and Prettier.
2. Blocks commits when generated code or docs drift.
> **Why this step?** Keeps reviewers focused on logical changes, not whitespace.
> **STOP-SIGN:** Local only.

## Rung 1 — Terraform Static Analysis (`make validate:tf:static`)
1. Invokes `tools/terraform/preflight.sh static`.
2. Performs `terraform fmt -check`, `tflint --recursive`, `tfsec --soft-fail`, `checkov -s`.
3. Runs `terraform init -backend=false` and `terraform validate` inside every `terraform/environments/*` directory.
> **Why this step?** Guarantees HCL correctness and provider compatibility while everything still points to mock providers.
> **STOP-SIGN:** Local only.

## Rung 2 — Policy as Code (`make validate:tf:policy`)
1. Calls `tools/terraform/preflight.sh policy`.
2. Generates a local `plan.out`/`plan.json` per environment with `TF_VAR_use_mock=true` (no state backend, no cloud credentials).
3. Executes `conftest test -p policy/opa plan.json` to enforce guardrails:
   - `deny-expensive.tf.rego` blocks high-risk SKUs.
   - `guardrails.tf.rego` ensures tags, encryption, TTL hours, and region allowlists.
> **Why this step?** Automates platform guardrails so reviewers only see compliant plans.
> **STOP-SIGN:** Local only.

## Rung 3 — Local Cloud Plan (`make validate:tf:plan-local`)
1. Wraps `tools/terraform/plan_local.sh`.
2. Produces human-readable plan output and JSON for the cost stage.
> **Why this step?** Gives change visibility without remote state or credentials.
> **STOP-SIGN:** Local only.

## Rung 4 — Cost Estimation (`make validate:cost`)
1. Runs `tools/cost/estimate.sh` which depends on Infracost.
2. Consumes `plan.json` files, `tools/cost/infracost.toml`, and `tools/cost/usage.yml`.
3. Fails when `diffTotalMonthlyCost` exceeds `MAX_MONTHLY_DELTA` (default `50`).
> **Why this step?** Financial guardrail before human approval.
> **STOP-SIGN:** Local only.

## Rung 5 — Local Kubernetes Validation (`make validate:k8s:local`)
1. Renders overlays with `kustomize build kubernetes/overlays/aws` and `kustomize build kubernetes/overlays/gcp`.
2. Validates schemas with `kubeconform -summary`.
3. Uses KinD (`tools/local/kind-setup.sh`) to run `kubectl apply --server-side --dry-run=server` and `kubectl diff`.
> **Why this step?** Ensures Argo CD and External Secrets manifests converge in a local control plane.
> **STOP-SIGN:** Local only.

## Rung 6 — Offline Smoke Tests (`make validate:smoke:offline`)
1. Spins the docker-compose stack, ensures CoreDNS resolves `api.arlo-resilience.com` to `127.0.0.1`.
2. Reuses `tests/smoke.sh` with `LOCAL_MODE=1` and `curl --insecure` against the local ingress.
3. Asserts DNS data-plane behaviour via `tests/dns_check.py` pointing at the stub resolver.
> **Why this step?** Validates behaviour end-to-end with zero cloud impact.
> **STOP-SIGN:** Local only.

## Rung 7 — Ephemeral Sandbox (`docs/APPENDIX_SAFE_APPLY.md`)
1. Spins a TTL-tagged stack in isolated AWS/GCP accounts using `terraform apply` behind feature flags.
2. GitHub Actions auto-destroys the stack via scheduled workflow before TTL expiry.
> **Why this step?** Gives occasional real-cloud rehearsal while enforcing cleanup discipline.
> **STOP-SIGN:** Billable resources—requires explicit approval.
