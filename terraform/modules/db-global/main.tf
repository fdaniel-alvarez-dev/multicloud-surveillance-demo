terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "table_name" {
  description = "Name of the DynamoDB global table"
  type        = string
}

variable "billing_mode" {
  description = "Billing mode for the table"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "hash_key" {
  description = "Partition key attribute"
  type        = string
}

variable "range_key" {
  description = "Sort key attribute"
  type        = string
  default     = null
}

variable "attributes" {
  description = "List of attribute definitions"
  type = list(object({
    name = string
    type = string
  }))
}

variable "replica_regions" {
  description = "AWS regions to replicate the table to"
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to the table"
  type        = map(string)
  default     = {}
}

locals {
  base_tags = merge({
    "Project"     = "arlo-resilience",
    "Service"     = "dynamodb",
    "Environment" = "prod"
  }, var.tags)
}

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = var.billing_mode
  hash_key     = var.hash_key
  range_key    = var.range_key

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "replica" {
    for_each = var.replica_regions
    content {
      region_name = replica.value
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(local.base_tags, {
    "Name" = var.table_name
  })
}

output "table_arn" {
  description = "ARN of the DynamoDB global table"
  value       = aws_dynamodb_table.this.arn
}

output "table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.this.name
}
