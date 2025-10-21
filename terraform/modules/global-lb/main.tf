terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "root_domain" {
  description = "Root DNS zone used for public records"
  type        = string
}

variable "record_name" {
  description = "Relative record name for the application"
  type        = string
}

variable "primary_dns_name" {
  description = "Primary endpoint served from AWS"
  type        = string
}

variable "secondary_dns_name" {
  description = "Secondary endpoint served from GCP"
  type        = string
}

variable "health_check_path" {
  description = "Path used for Route 53 health checks"
  type        = string
  default     = "/health"
}

variable "health_check_port" {
  description = "Port used for health checks"
  type        = number
  default     = 80
}

variable "tags" {
  description = "Tags applied to Route 53 resources"
  type        = map(string)
  default     = {}
}

locals {
  base_tags = merge({
    "Project" = "arlo-resilience",
    "Service" = "global-routing"
  }, var.tags)

  record_fqdn = "${var.record_name}.${var.root_domain}"
}

resource "aws_route53_zone" "primary" {
  name = var.root_domain
  tags = merge(local.base_tags, {
    "Name" = var.root_domain
  })
}

resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_dns_name
  port              = var.health_check_port
  type              = "HTTP"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30
  tags = merge(local.base_tags, {
    "Scope" = "primary"
  })
}

resource "aws_route53_health_check" "secondary" {
  fqdn              = var.secondary_dns_name
  port              = var.health_check_port
  type              = "HTTP"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30
  tags = merge(local.base_tags, {
    "Scope" = "secondary"
  })
}

resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = local.record_fqdn
  type    = "CNAME"
  ttl     = 60

  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary.id
  records         = [var.primary_dns_name]
}

resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = local.record_fqdn
  type    = "CNAME"
  ttl     = 60

  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  health_check_id = aws_route53_health_check.secondary.id
  records         = [var.secondary_dns_name]
}

output "zone_id" {
  description = "Public hosted zone ID"
  value       = aws_route53_zone.primary.zone_id
}

output "record_fqdn" {
  description = "Fully qualified DNS record"
  value       = aws_route53_record.primary.fqdn
}
