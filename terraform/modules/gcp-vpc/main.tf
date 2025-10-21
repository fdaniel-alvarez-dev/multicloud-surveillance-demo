terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

variable "name" {
  description = "Base name for the GCP network"
  type        = string
}

variable "project_id" {
  description = "GCP project where the network will be created"
  type        = string
}

variable "region" {
  description = "Primary region for the subnets"
  type        = string
}

variable "ip_range" {
  description = "CIDR range for the VPC network"
  type        = string
}

variable "subnets" {
  description = "Map of subnet names to CIDR ranges"
  type        = map(string)
}

variable "tags" {
  description = "Labels applied to resources"
  type        = map(string)
  default     = {}
}

locals {
  labels = merge({
    project = "arlo-resilience",
    module  = "gcp-vpc"
  }, { for k, v in var.tags : lower(k) => v })
}

resource "google_compute_network" "this" {
  name                    = "${var.name}-network"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
  delete_default_routes_on_create = false

  labels = local.labels
}

resource "google_compute_subnetwork" "this" {
  for_each               = var.subnets
  name                   = "${var.name}-${each.key}-subnet"
  project                = var.project_id
  region                 = var.region
  network                = google_compute_network.this.id
  ip_cidr_range          = each.value
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${each.key}-pods"
    ip_cidr_range = cidrsubnet(each.value, 4, 4)
  }

  secondary_ip_range {
    range_name    = "${each.key}-services"
    ip_cidr_range = cidrsubnet(each.value, 4, 5)
  }

  log_config {
    aggregation_interval = "INTERVAL_5_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  labels = local.labels
}

resource "google_compute_firewall" "intra_cluster" {
  name    = "${var.name}-allow-cluster"
  project = var.project_id
  network = google_compute_network.this.name

  direction = "INGRESS"
  priority  = 1000

  allows {
    protocol = "tcp"
    ports    = ["443", "10250", "10257", "10259"]
  }

  source_ranges = [var.ip_range]
  target_tags   = ["${var.name}-cluster"]

  labels = local.labels
}

resource "google_compute_firewall" "health_checks" {
  name    = "${var.name}-allow-healthchecks"
  project = var.project_id
  network = google_compute_network.this.name

  direction = "INGRESS"
  priority  = 1000

  allows {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["${var.name}-ingress"]

  labels = local.labels
}

output "network_name" {
  description = "Name of the created VPC network"
  value       = google_compute_network.this.name
}

output "subnet_ids" {
  description = "Self links of the defined subnets"
  value       = [for s in google_compute_subnetwork.this : s.self_link]
}

output "pod_secondary_ranges" {
  description = "Secondary ranges used for pod networking"
  value       = { for name, subnet in google_compute_subnetwork.this : name => subnet.secondary_ip_range[0].range_name }
}

output "subnet_names" {
  description = "Names of created subnetworks keyed by logical name"
  value       = { for name, subnet in google_compute_subnetwork.this : name => subnet.name }
}
