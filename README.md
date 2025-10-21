# Multi-Cloud Warm Standby for Arlo

This repository provisions a production-ready warm-standby environment for Arlo's resilience project. The stack spans AWS and GCP, keeping both clouds warm while directing live traffic to AWS with automated fail-over to GCP when health checks detect issues.

## Architecture Highlights
- **Terraform 1.6 modules** provision VPCs, EKS, GKE Autopilot, DynamoDB global tables, Route 53 fail-over records, and supporting networking.
- **Kubernetes** runs the `arlo-demo-app` microservice in both clusters with External Secrets pulling credentials from AWS Secrets Manager and GCP Secret Manager.
- **CI/CD** uses Atlantis to manage Terraform changes, GitHub Actions to build and publish the container image to Amazon ECR and Artifact Registry, and Argo CD ApplicationSet to sync Kubernetes overlays to each cluster.
- **Observability** provides Prometheus federation, CloudWatch and Cloud Monitoring exporters, and a Grafana dashboard tracking latency, error budget, and replication lag.
- **Automation** includes a fail-over simulation script and smoke tests validating DNS, health checks, and service responses.

## Prerequisites
1. **Tooling**
   - Terraform ≥ 1.6
   - kubectl ≥ 1.28
   - helm ≥ 3.12 (for Argo CD installation)
   - awscli ≥ 2.13 and gcloud ≥ 445
2. **Cloud Accounts**
   - AWS account with permissions to create VPC, EKS, IAM, DynamoDB, Route 53, and S3 resources.
   - GCP project with billing enabled and permissions for GKE, VPC, DNS, Artifact Registry, and Secret Manager.
3. **State Buckets**
   - S3 bucket `arlo-terraform-state` and DynamoDB table `arlo-terraform-locks` for AWS environments.
   - GCS bucket `arlo-terraform-state` for GCP environments.
4. **Secrets**
   - AWS Secrets Manager secret `arlo/prod/api` containing at least keys `apiKey` and `dynamoEndpoint`.
   - GCP Secret Manager secret `arlo-api` storing equivalent JSON values.
5. **CI/CD Secrets** (configured in GitHub repository settings)
   - `ATLANTIS_URL`, `ATLANTIS_TOKEN`
   - `AWS_DEPLOY_ROLE_ARN`
   - `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_BUILD_SERVICE_ACCOUNT`
   - `ARGOCD_SERVER`, `ARGOCD_AUTH_TOKEN`

## Terraform Usage
Initialise Terraform for each environment using the shared backend variables file:

```bash
cd terraform/environments/prod-aws
terraform init -backend-config=../backend.tfvars
terraform plan
terraform apply
```

Repeat for GCP:

```bash
cd terraform/environments/prod-gcp
terraform init -backend-config=../backend.tfvars
terraform apply
```

Terraform automatically provisions networking, clusters, DynamoDB, global DNS, and GCP DNS records.

## Atlantis
1. Deploy Atlantis (e.g., via Helm) pointing to this repository.
2. Mount `/etc/atlantis/config.yml` with the provided `ci-cd/atlantis/config.yaml`.
3. Ensure GitHub webhooks are enabled for pull request events; GitHub Actions also posts to Atlantis via the `atlantis-plan` job.

## Kubernetes via Argo CD
1. Install Argo CD using the provided Helm values:
   ```bash
   helm repo add argo https://argoproj.github.io/argo-helm
   helm upgrade --install argocd argo/argo-cd \
     --namespace argocd --create-namespace \
     -f ci-cd/argocd/values.yaml
   ```
2. Apply the ApplicationSet:
   ```bash
   kubectl apply -f ci-cd/argocd/applicationset.yaml
   ```
3. Argo CD will create applications targeting:
   - `aws-eks` context -> `kubernetes/overlays/aws`
   - `gcp-gke` context -> `kubernetes/overlays/gcp`

## CI/CD Workflow
The GitHub Actions workflow (`.github/workflows/multi-cloud-pipeline.yaml`) performs:
1. **Atlantis trigger** on pull requests for Terraform plans.
2. **Multi-architecture build** of `arlo-demo-app`, publishing to Amazon ECR and Artifact Registry on pushes to `main`.
3. **Manifest updates** to set the latest image tag and trigger Argo CD sync.
4. **Smoke tests** using `tests/smoke.sh` against `api.arlo-resilience.com`.

## Monitoring Stack
- Deploy Prometheus with the configuration in `monitoring/prometheus/prometheus.yml`.
- Import the Grafana dashboard from `monitoring/grafana/dashboards/arlo_overview.json`.
- Configure exporters:
  - `cloudwatch-exporter` for AWS metrics.
  - `stackdriver-exporter` for GCP Cloud Monitoring metrics.
- Alerts should target `alertmanager.monitoring.svc:9093` as referenced in the Prometheus configuration.

## Simulating Fail-over
Use the helper script to simulate an AWS outage and trigger DNS fail-over:

```bash
./scripts/simulate_failover.sh \
  arn:aws:eks:us-east-1:741852963000:cluster/arlo-eks-cluster \
  https://api.gcp.arlo-resilience.com
```

The script scales the AWS deployment to zero, waits for pods to terminate, and hits the GCP health endpoint to satisfy Route 53 checks. Monitor the Grafana dashboard or DNS records to verify traffic migration.

## Tests
Run smoke and DNS checks locally or in CI:

```bash
./tests/smoke.sh api.arlo-resilience.com
./tests/dns_check.py api.arlo-resilience.com
```

## Safety & Validation Toolkit
- **From-zero deployment:** [`docs/DEPLOYMENT_GUIDE_FROM_ZERO.md`](docs/DEPLOYMENT_GUIDE_FROM_ZERO.md) explains the safety model, tooling prerequisites, and optional production apply once all validations pass.
- **Validation ladder reference:** [`docs/VALIDATION_LADDER.md`](docs/VALIDATION_LADDER.md) breaks down each rung and its associated command.
- **Local emulation:** [`docs/LOCAL_EMULATION.md`](docs/LOCAL_EMULATION.md) documents the Docker/KinD stack, fake SecretStore, and DNS stubbing used for offline tests.
- **Ephemeral apply appendix:** [`docs/APPENDIX_SAFE_APPLY.md`](docs/APPENDIX_SAFE_APPLY.md) covers opt-in, TTL-tagged sandbox applies.

### Make Targets
Include `tools/make/Makefile.validate` (already wired into the root `Makefile`) to access the validation ladder locally:

```bash
make validate:repo           # Rung 0 — pre-commit hygiene
make validate:tf:static      # Rung 1 — Terraform fmt/tflint/tfsec/checkov
make validate:tf:policy      # Rung 2 — OPA/Conftest guardrails
make validate:tf:plan-local  # Rung 3 — local plan + JSON
make validate:cost           # Rung 4 — Infracost threshold gate
make validate:k8s:local      # Rung 5 — KinD render + dry-run
make validate:smoke:offline  # Rung 6 — offline smoke and DNS stub
```

### Offline CI Workflow
Pull requests automatically run the offline-only chain via `.github/workflows/validate-only.yml`. The job spins up Docker compose services (LocalStack, DynamoDB Local, KinD bootstrap, CoreDNS), executes the ladder targets, and tears everything down without touching AWS or GCP.

## Repository Layout
```
terraform/              # Infrastructure as code modules and environment compositions
kubernetes/             # Base and overlay manifests deployed via Argo CD
ci-cd/                  # Atlantis and Argo CD configuration plus workflow automation
monitoring/             # Prometheus configuration and Grafana dashboard
scripts/                # Operations scripts (fail-over simulation)
tests/                  # Smoke tests for health and DNS validation
```
