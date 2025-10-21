terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

locals {
  base_tags = merge({
    "Project"      = "arlo-resilience",
    "Environment"  = "prod",
    "Cluster"      = var.cluster_name,
    "ManagedBy"    = "terraform",
    "Service"      = "eks"
  }, var.tags)
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "eks_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-iam-role"
  assume_role_policy = data.aws_iam_policy_document.eks_trust.json
  tags               = local.base_tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-controlplane"
  description = "EKS control plane security group"
  vpc_id      = var.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  tags = merge(local.base_tags, {
    "Name" = "${var.cluster_name}-controlplane-sg"
  })
}

resource "aws_security_group_rule" "cluster_api" {
  description              = "Allow nodes to communicate with cluster API"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
}

resource "aws_security_group" "nodes" {
  name        = "${var.cluster_name}-nodes"
  description = "Security group for worker nodes"
  vpc_id      = var.vpc_id

  ingress {
    description      = "Allow node to node communication"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    self             = true
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  tags = merge(local.base_tags, {
    "Name" = "${var.cluster_name}-nodes-sg"
  })
}

resource "aws_security_group_rule" "nodes_api" {
  description       = "Allow control plane to communicate with nodes"
  type              = "ingress"
  from_port         = 1024
  to_port           = 65535
  protocol          = "tcp"
  security_group_id = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    endpoint_public_access = var.endpoint_public_access
    endpoint_private_access = true
    security_group_ids     = [aws_security_group.cluster.id]
    subnet_ids             = concat(var.private_subnet_ids, var.public_subnet_ids)
  }

  kubernetes_network_config {
    service_ipv4_cidr = var.service_ipv4_cidr
  }

  enabled_cluster_log_types = ["api", "authenticator", "controllerManager", "scheduler"]

  tags = merge(local.base_tags, {
    "Name" = var.cluster_name
  })
}

resource "aws_iam_role" "node" {
  for_each = var.node_groups

  name = "${var.cluster_name}-${each.key}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.base_tags
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  for_each   = aws_iam_role.node
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = each.value.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  for_each   = aws_iam_role.node
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = each.value.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  for_each   = aws_iam_role.node
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = each.value.name
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-${each.key}"
  node_role_arn   = aws_iam_role.node[each.key].arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  ami_type       = "AL2_x86_64"
  disk_size      = each.value.disk_size
  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy
  ]

  tags = merge(local.base_tags, {
    "NodeGroup" = each.key
  })
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "eks_pod_identity_agent" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
}

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "karpenter_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.karpenter_namespace}:${var.karpenter_service_account_name}"]
    }

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }
  }
}

resource "aws_iam_role" "karpenter" {
  count              = var.karpenter_enabled ? 1 : 0
  name               = "${var.cluster_name}-karpenter"
  assume_role_policy = data.aws_iam_policy_document.karpenter_assume.json
  tags               = local.base_tags
}

resource "aws_iam_role_policy" "karpenter_controller" {
  count = var.karpenter_enabled ? 1 : 0

  name = "${var.cluster_name}-karpenter-controller"
  role = aws_iam_role.karpenter[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateLaunchTemplate", "ec2:CreateFleet", "ec2:RunInstances", "ec2:TerminateInstances", "ec2:Describe*"],
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"],
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"],
        Resource = [for role in aws_iam_role.node : role.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_spot" {
  count      = var.karpenter_enabled ? 1 : 0
  role       = aws_iam_role.karpenter[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2SpotFleetTaggingRole"
}
