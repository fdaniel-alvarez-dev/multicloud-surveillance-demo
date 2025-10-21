output "name" {
  description = "Name of the GKE Autopilot cluster"
  value       = google_container_cluster.this.name
}

output "endpoint" {
  description = "Endpoint of the GKE API server"
  value       = google_container_cluster.this.endpoint
}

output "master_version" {
  description = "Master version in use"
  value       = google_container_cluster.this.master_version
}
