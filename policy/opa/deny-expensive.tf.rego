package arlo.expensive

# Helper to fetch all resource change objects regardless of plan layout.
resource_changes := input.resource_changes

default resource_changes := []

disallowed_instance_types := {
  "m5.4xlarge",
  "m5.8xlarge",
  "c5.9xlarge",
  "c5.12xlarge",
  "r6i.4xlarge",
  "r6i.8xlarge",
  "db.r5.2xlarge",
  "db.r5.4xlarge",
  "db.m5.4xlarge",
}

# Deny overly large AWS instances used in local/testing contexts.
deny[msg] {
  rc := resource_changes[_]
  rc.type == "aws_instance"
  after := rc.change.after
  instance_type := after.instance_type
  disallowed_instance_types[instance_type]
  msg := sprintf("aws_instance %s uses disallowed instance_type %s", [rc.name, instance_type])
}

# Deny EKS node groups that scale too large for sandbox usage.
deny[msg] {
  rc := resource_changes[_]
  rc.type == "aws_eks_node_group"
  after := rc.change.after
  scaling := object.get(after, "scaling_config", {})
  desired := object.get(scaling, "desired_size", 0)
  desired > 3
  msg := sprintf("aws_eks_node_group %s desired_size %d exceeds safety cap (3)", [rc.name, desired])
}

# Deny GKE node pools that exceed safe node counts.
deny[msg] {
  rc := resource_changes[_]
  rc.type == "google_container_node_pool"
  after := rc.change.after
  autoscaling := object.get(after, "autoscaling", {})
  max_nodes := object.get(autoscaling, "max_node_count", 0)
  max_nodes > 3
  msg := sprintf("google_container_node_pool %s max_node_count %d exceeds safety cap (3)", [rc.name, max_nodes])
}

# Deny DynamoDB tables provisioned with expensive throughput when mocks should be used.
deny[msg] {
  rc := resource_changes[_]
  rc.type == "aws_dynamodb_table"
  after := rc.change.after
  not after.billing_mode == "PAY_PER_REQUEST"
  read := object.get(after, "read_capacity", 0)
  write := object.get(after, "write_capacity", 0)
  read > 5
  write > 5
  msg := sprintf("aws_dynamodb_table %s provisioned capacity (%d/%d) exceeds mock allowance (5)", [rc.name, read, write])
}

# Deny AWS load balancers when use_mock flag should skip them.
deny[msg] {
  rc := resource_changes[_]
  rc.type == "aws_lb"
  after := rc.change.after
  tags := object.get(after, "tags", {})
  use_mock := object.get(tags, "use_mock", "false")
  use_mock != "true"
  msg := sprintf("aws_lb %s must be skipped (set use_mock=true)", [rc.name])
}

# Deny GCP global addresses that are not skipped in mock mode.
deny[msg] {
  rc := resource_changes[_]
  rc.type == "google_compute_global_address"
  labels := object.get(rc.change.after, "labels", {})
  use_mock := object.get(labels, "use_mock", "false")
  use_mock != "true"
  msg := sprintf("google_compute_global_address %s must be skipped (set use_mock=true)", [rc.name])
}
