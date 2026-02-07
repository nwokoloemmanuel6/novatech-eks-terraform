# -----------------------------------------------------------------------------
# Root Module - Orchestrates VPC, EKS, and Node Groups
# -----------------------------------------------------------------------------

locals {
  cluster_name = "${var.project_name}-${var.environment}-cluster"
}

# -----------------------------------------------------------------------------
# VPC - Using Terraform Registry Module
# -----------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs            = var.availability_zones
  public_subnets = var.public_subnet_cidrs

  enable_nat_gateway      = false  # No NAT - nodes run on public subnets
  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = true   # Required for public subnet nodes

  # EKS subnet tagging
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = 1
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# EKS Cluster - Using Custom Module
# -----------------------------------------------------------------------------

module "eks" {
  source = "./modules/eks"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnets
  environment     = var.environment
}

# -----------------------------------------------------------------------------
# Node Groups - Using Custom Module
# -----------------------------------------------------------------------------

module "node_group" {
  source = "./modules/node_group"

  cluster_name = module.eks.cluster_name
  subnet_ids   = module.vpc.public_subnets
  environment  = var.environment

  node_groups = {
    general = {
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"
      desired_size   = var.node_desired_size
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      labels = {
        "role" = "general"
      }
    }
  }

  depends_on = [module.eks]
}

# -----------------------------------------------------------------------------
# IAM User for Programmatic Access (CI/CD)
# -----------------------------------------------------------------------------

resource "aws_iam_user" "eks_admin" {
  name = "${var.project_name}-eks-admin"
  path = "/system/"

  tags = {
    Environment = var.environment
    Purpose     = "EKS cluster administration"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_user_policy" "eks_admin" {
  name = "${var.project_name}-eks-admin-policy"
  user = aws_iam_user.eks_admin.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      }
    ]
  })
}
