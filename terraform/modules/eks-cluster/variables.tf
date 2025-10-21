variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the control plane"
  type        = string
  default     = "1.28"
}

variable "region" {
  description = "AWS region where the cluster runs"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID that hosts the cluster"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets used by worker nodes"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnets for load balancers"
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Whether the cluster endpoint is public"
  type        = bool
  default     = true
}

variable "node_groups" {
  description = "Map of node group configurations"
  type = map(object({
    instance_types      = list(string)
    desired_size        = number
    max_size            = number
    min_size            = number
    disk_size           = number
    capacity_type       = string
    labels              = map(string)
    taints              = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))
  default = {
    primary = {
      instance_types = ["m6i.xlarge"]
      desired_size   = 2
      max_size       = 5
      min_size       = 2
      disk_size      = 50
      capacity_type  = "ON_DEMAND"
      labels = {
        "workload" = "general"
      }
      taints = []
    }
  }
}

variable "tags" {
  description = "Tags propagated to all resources"
  type        = map(string)
  default     = {}
}

variable "karpenter_enabled" {
  description = "Whether to configure the IAM role for Karpenter"
  type        = bool
  default     = true
}

variable "karpenter_namespace" {
  description = "Namespace where Karpenter will be installed"
  type        = string
  default     = "karpenter"
}

variable "karpenter_service_account_name" {
  description = "Service account name used by Karpenter"
  type        = string
  default     = "karpenter-controller"
}

variable "service_ipv4_cidr" {
  description = "Service CIDR for the cluster"
  type        = string
  default     = "172.20.0.0/16"
}
