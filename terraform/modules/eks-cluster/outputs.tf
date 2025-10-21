output "cluster_name" {
  description = "Name of the provisioned EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint of the EKS cluster"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 encoded certificate authority data"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group ID for the control plane"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group ID assigned to worker nodes"
  value       = aws_security_group.nodes.id
}

output "karpenter_role_arn" {
  description = "IAM role ARN that Karpenter uses to manage capacity"
  value       = var.karpenter_enabled ? aws_iam_role.karpenter[0].arn : null
}
