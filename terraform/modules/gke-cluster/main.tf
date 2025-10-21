terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

locals {
  labels = merge({
    project = "arlo-resilience",
    environment = "prod",
    service = "gke"
  }, { for k, v in var.labels : lower(k) => v })
}

resource "google_project_service" "container" {
  project = var.project_id
  service = "container.googleapis.com"
}

resource "google_project_service" "monitoring" {
  project = var.project_id
  service = "monitoring.googleapis.com"
}

resource "google_project_service" "logging" {
  project = var.project_id
  service = "logging.googleapis.com"
}

resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region

  enable_autopilot = true
  project          = var.project_id

  network    = var.network
  subnetwork = var.subnetwork

  release_channel {
    channel = var.release_channel
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  master_authorized_networks_config {
    cidr_blocks = [{
      cidr_block   = "10.0.0.0/8"
      display_name = "internal"
    }]
  }

  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T02:00:00Z"
      end_time   = "2024-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SU"
    }
  }

  resource_labels = local.labels

  depends_on = [
    google_project_service.container,
    google_project_service.monitoring,
    google_project_service.logging
  ]
}
