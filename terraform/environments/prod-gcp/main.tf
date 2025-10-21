terraform {
  required_version = ">= 1.6"
  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "arlo-resilience-prod"
}

variable "region" {
  description = "Primary GCP region"
  type        = string
  default     = "us-central1"
}

variable "labels" {
  description = "Default labels"
  type        = map(string)
  default = {
    environment = "prod"
    team        = "platform"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "vpc" {
  source = "../../modules/gcp-vpc"

  name       = "arlo-prod"
  project_id = var.project_id
  region     = var.region
  ip_range   = "10.30.0.0/16"
  subnets = {
    zone-a = "10.30.10.0/24"
    zone-b = "10.30.11.0/24"
  }
  tags = var.labels
}

module "gke" {
  source = "../../modules/gke-cluster"

  project_id    = var.project_id
  region        = var.region
  cluster_name  = "arlo-gke-cluster"
  network       = module.vpc.network_name
  subnetwork    = module.vpc.subnet_names["zone-a"]
  release_channel = "REGULAR"
  locations       = ["${var.region}-a", "${var.region}-b"]
  labels          = var.labels
}

resource "google_compute_global_address" "gke_ingress" {
  name    = "arlo-gke-global-ip"
  project = var.project_id
  labels  = { for k, v in var.labels : lower(k) => v }
}

resource "google_dns_managed_zone" "gcp" {
  name        = "arlo-resilience-gcp"
  dns_name    = "gcp.arlo-resilience.com."
  project     = var.project_id
  description = "Delegated zone for the GCP secondary endpoint"

  labels = { for k, v in var.labels : lower(k) => v }
}

resource "google_dns_record_set" "service" {
  name         = "api.gcp.arlo-resilience.com."
  managed_zone = google_dns_managed_zone.gcp.name
  type         = "A"
  ttl          = 60
  project      = var.project_id

  rrdatas = [google_compute_global_address.gke_ingress.address]
}

output "gke_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = module.gke.endpoint
}

output "gcp_service_ip" {
  description = "Global IP allocated for the GCP entry point"
  value       = google_compute_global_address.gke_ingress.address
}
