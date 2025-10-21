# Local-Only Emulation

This guide explains how to mirror the platform locally with zero cloud calls. Combine it with the validation ladder for fast feedback loops.

## 1. Start Supporting Services
1. ```bash
   docker compose -f tools/local/docker-compose.local.yml up -d
   ```
2. Services exposed:
   - `localstack`: IAM, SSM, Secrets Manager, Route53, and S3 APIs.
   - `dynamodb-local`: Global table stub using shared DB path.
   - `kind-bootstrap`: one-shot container invoking `tools/local/kind-setup.sh`.
   - `coredns`: answers `api.arlo-resilience.com` -> `127.0.0.1` and relays the rest upstream.
> **Why this step?** Ensures Terraform, External Secrets, and DNS checks run without touching AWS/GCP.
> **STOP-SIGN:** Docker-only workloads.

## 2. Create/Refresh KinD Cluster
1. The compose service `kind-bootstrap` runs on first `up`; re-run manually if you need to refresh:
   ```bash
   tools/local/kind-setup.sh --force-recreate
   ```
2. Cluster features:
   - Ingress controller (`ingress-nginx`) reachable on `127.0.0.1:8443`.
   - Argo CD installed with values that disable cloud webhooks (`ci-cd/argocd/local-values.yaml` auto-generated).
   - External Secrets with a `SecretStore` pointing to LocalStack Secrets Manager.
3. Validate connectivity:
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```
> **Why this step?** Proves the KinD control plane is ready before running K8s validation.
> **STOP-SIGN:** Local only.

## 3. Wire Terraform to LocalStack
1. Export the following environment variables before running the Terraform scripts:
   ```bash
   export AWS_ACCESS_KEY_ID=test
   export AWS_SECRET_ACCESS_KEY=test
   export AWS_DEFAULT_REGION=us-east-1
   export AWS_ENDPOINT_URL=http://localhost:4566
   export TF_VAR_use_mock=true
   ```
2. Set the AWS provider snippet in a `.tfvars` override if needed:
   ```hcl
   provider "aws" {
     region                      = "us-east-1"
     access_key                  = var.mock_access_key
     secret_key                  = var.mock_secret_key
     s3_force_path_style         = true
     skip_credentials_validation = true
     skip_metadata_api_check     = true
     endpoints = {
       sts       = "http://localhost:4566"
       dynamodb  = "http://localhost:4566"
       secretsmanager = "http://localhost:4566"
       route53   = "http://localhost:4566"
     }
   }
   ```
> **Why this step?** Redirects AWS SDK calls to LocalStack when modules bypass `use_mock` for tests.
> **STOP-SIGN:** Local only.

## 4. Provide Mock Outputs for Downstream Modules
1. Each Terraform module accepts `var.use_mock`. Example pattern:
   ```hcl
   locals {
     global_lb_hostname = var.use_mock ? "mock-global.arlo" : module.route53_primary.fqdn
   }

   output "global_lb_hostname" {
     value = local.global_lb_hostname
   }
   ```
2. DynamoDB global tables should surface fake endpoints when mocked so the application chart can build Kubernetes ConfigMaps.
> **Why this step?** Keeps dependencies satisfied even when resources are skipped via `count = 0`.
> **STOP-SIGN:** Local only.

## 5. Offline Application Smoke
1. With compose stack running, deploy manifests to KinD:
   ```bash
   make validate:k8s:local
   ```
2. Run offline smoke tests:
   ```bash
   make validate:smoke:offline
   ```
3. Inspect logs:
   ```bash
   kubectl logs -n arlo arlo-demo-app-0
   docker compose -f tools/local/docker-compose.local.yml logs coredns
   ```
> **Why this step?** Confirms the local ingress, DNS stub, and app health match production expectations.
> **STOP-SIGN:** Local only.

## 6. Tear Down
1. ```bash
   docker compose -f tools/local/docker-compose.local.yml down
   kind delete cluster --name arlo-local
   ```
2. Remove the KinD kubeconfig entry if desired:
   ```bash
   kubectl config delete-context kind-arlo-local
   ```
> **Why this step?** Ensures local resources do not keep consuming CPU/RAM.
> **STOP-SIGN:** Local only.
