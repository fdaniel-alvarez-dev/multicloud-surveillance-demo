package arlo.guardrails

resource_changes := input.resource_changes

default resource_changes := []

allowed_aws_regions := {"us-east-1", "us-west-2"}
allowed_gcp_regions := {"us-central1", "us-east1"}

required_tags := ["owner", "environment", "ttl_hours"]

# Require tagging on AWS resources.
deny[msg] {
  rc := resource_changes[_]
  startswith(rc.type, "aws_")
  after := rc.change.after
  tags := object.get(after, "tags", {})
  some tag
  tag := required_tags[_]
  value := object.get(tags, tag, "")
  value == ""
  msg := sprintf("%s %s missing required tag '%s'", [rc.type, rc.name, tag])
}

# Require labels on GCP resources.
deny[msg] {
  rc := resource_changes[_]
  startswith(rc.type, "google_")
  after := rc.change.after
  labels := object.get(after, "labels", {})
  some tag
  tag := required_tags[_]
  value := object.get(labels, tag, "")
  value == ""
  msg := sprintf("%s %s missing required label '%s'", [rc.type, rc.name, tag])
}

# ttl_hours must be numeric and within limits.
deny[msg] {
  rc := resource_changes[_]
  after := rc.change.after
  tags := object.get(after, "tags", {})
  ttl := object.get(tags, "ttl_hours", "0")
  not is_number_string(ttl)
  msg := sprintf("%s %s ttl_hours must be numeric", [rc.type, rc.name])
}

deny[msg] {
  rc := resource_changes[_]
  after := rc.change.after
  tags := object.get(after, "tags", {})
  ttl := to_number(object.get(tags, "ttl_hours", "0"))
  ttl > 24
  msg := sprintf("%s %s ttl_hours (%v) exceeds 24 hour cap", [rc.type, rc.name, ttl])
}

# Enforce AWS region allowlist.
deny[msg] {
  rc := resource_changes[_]
  startswith(rc.type, "aws_")
  after := rc.change.after
  region := object.get(after, "region", "")
  region != ""
  not allowed_aws_regions[region]
  msg := sprintf("%s %s targets region %s which is outside the allowlist", [rc.type, rc.name, region])
}

# Enforce GCP region allowlist.
deny[msg] {
  rc := resource_changes[_]
  startswith(rc.type, "google_")
  after := rc.change.after
  location := object.get(after, "location", object.get(after, "region", ""))
  location != ""
  not allowed_gcp_regions[location]
  msg := sprintf("%s %s targets region %s which is outside the allowlist", [rc.type, rc.name, location])
}

# Require encryption config on EKS clusters.
deny[msg] {
  rc := resource_changes[_]
  rc.type == "aws_eks_cluster"
  after := rc.change.after
  encryption := object.get(after, "encryption_config", [])
  count(encryption) == 0
  msg := sprintf("aws_eks_cluster %s must enable encryption_config", [rc.name])
}

# Require private endpoint on DynamoDB global tables when mocks disabled.
deny[msg] {
  rc := resource_changes[_]
  rc.type == "aws_dynamodb_table"
  after := rc.change.after
  tags := object.get(after, "tags", {})
  use_mock := object.get(tags, "use_mock", "false")
  use_mock != "true"
  object.get(after, "server_side_encryption", null) == null
  msg := sprintf("aws_dynamodb_table %s requires server_side_encryption when use_mock=false", [rc.name])
}

#############################
# Helper Functions
#############################

# Returns true when input string can be parsed to number.
is_number_string(val) {
  to_number(val)
}
