terraform {
  required_version = ">= 1.6"
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "aws_region" {
  description = "AWS region hosting the primary stack"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Default tags for AWS resources"
  type        = map(string)
  default = {
    Environment = "prod"
    Team        = "platform"
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  vpc_name = "arlo-prod"
}

module "vpc" {
  source = "../../modules/aws-vpc"

  name           = "${local.vpc_name}"
  cidr_block     = "10.20.0.0/16"
  azs            = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets = ["10.20.0.0/24", "10.20.1.0/24"]
  private_subnets = ["10.20.10.0/24", "10.20.11.0/24"]
  tags           = var.tags
}

module "eks" {
  source = "../../modules/eks-cluster"

  cluster_name        = "arlo-eks-cluster"
  cluster_version     = "1.28"
  region              = var.aws_region
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  endpoint_public_access = true
  service_ipv4_cidr   = "172.21.0.0/16"
  node_groups = {
    general = {
      instance_types = ["m6i.large"]
      desired_size   = 3
      max_size       = 6
      min_size       = 3
      disk_size      = 100
      capacity_type  = "ON_DEMAND"
      labels = {
        role = "primary"
        cluster = "aws"
      }
      taints = []
    }
    burst = {
      instance_types = ["m6i.xlarge"]
      desired_size   = 0
      max_size       = 4
      min_size       = 0
      disk_size      = 120
      capacity_type  = "SPOT"
      labels = {
        role = "karpenter"
        cluster = "aws"
      }
      taints = []
    }
  }
  tags = var.tags
}

module "global_table" {
  source = "../../modules/db-global"

  table_name      = "arlo-global-sessions"
  billing_mode    = "PAY_PER_REQUEST"
  hash_key        = "customer_id"
  range_key       = "event_time"
  attributes = [
    {
      name = "customer_id"
      type = "S"
    },
    {
      name = "event_time"
      type = "N"
    }
  ]
  replica_regions = [var.aws_region, "us-west-2"]
  tags            = var.tags
}

module "global_lb" {
  source = "../../modules/global-lb"

  root_domain         = "arlo-resilience.com"
  record_name         = "api"
  primary_dns_name    = "aws-api.arlo-resilience.com"
  secondary_dns_name  = "gcp-api.arlo-resilience.com"
  health_check_path   = "/health"
  health_check_port   = 80
  tags                = var.tags
}

output "eks_cluster_endpoint" {
  description = "Endpoint for the AWS EKS cluster"
  value       = module.eks.cluster_endpoint
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB global table"
  value       = module.global_table.table_name
}

output "route53_record" {
  description = "FQDN of the global failover record"
  value       = module.global_lb.record_fqdn
}
