variable "project_id" {
  description = "GCP project ID hosting the cluster"
  type        = string
}

variable "region" {
  description = "Region where the Autopilot cluster will live"
  type        = string
}

variable "network" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnetwork" {
  description = "Name of the subnetwork"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "release_channel" {
  description = "Release channel for the cluster"
  type        = string
  default     = "REGULAR"
}

variable "locations" {
  description = "Additional zones used by the cluster"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Resource labels applied to the cluster"
  type        = map(string)
  default     = {}
}
