locals {
  name = var.cluster_name

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  default_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Cluster     = var.cluster_name
  })

  # Node subnets from primary CIDR
  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 1)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 6, i)]
  intra_subnets   = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 6, i + 16)]

  # Pod subnets from secondary CIDR
  pod_subnets = [for i, az in local.azs : cidrsubnet(var.pod_cidr, 2, i)]
}
