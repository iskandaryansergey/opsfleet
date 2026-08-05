module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.intra_subnets

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  private_subnet_tags = {
    "karpenter.sh/discovery"          = local.name
    "kubernetes.io/role/internal-elb" = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
}

################################################################################
# Secondary CIDR and Pod Subnets
################################################################################

resource "aws_vpc_ipv4_cidr_block_association" "pod_cidr" {
  vpc_id     = module.vpc.vpc_id
  cidr_block = var.pod_cidr
}

resource "aws_subnet" "pod" {
  count = length(local.azs)

  vpc_id            = module.vpc.vpc_id
  cidr_block        = local.pod_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name                     = "${local.name}-pod-${local.azs[count.index]}"
    "karpenter.sh/discovery" = local.name
    "kubernetes.io/role/cni" = "1"
  }

  depends_on = [aws_vpc_ipv4_cidr_block_association.pod_cidr]
}

resource "aws_route_table_association" "pod" {
  count = length(local.azs)

  subnet_id      = aws_subnet.pod[count.index].id
  route_table_id = module.vpc.private_route_table_ids[count.index % length(module.vpc.private_route_table_ids)]
}

################################################################################
# VPC Endpoints
################################################################################

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.name}-vpc-endpoints-"
  description = "Security group for VPC interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC primary and pod CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.pod_cidr]
  }

  tags = {
    Name = "${local.name}-vpc-endpoints"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"

  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = {
    Name = "${local.name}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.region}.dynamodb"

  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = {
    Name = "${local.name}-dynamodb-endpoint"
  }
}

locals {
  interface_endpoints = toset([
    "ecr.api",
    "ecr.dkr",
    "sts",
    "logs",
    "sqs",
    "ssm",
    "ssmmessages",
    "ec2messages",
  ])
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type = "Interface"

  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name}-${each.value}-endpoint"
  }
}

################################################################################
# VPC Flow Logs
################################################################################

resource "aws_flow_log" "vpc" {
  vpc_id                   = module.vpc.vpc_id
  traffic_type             = "ALL"
  iam_role_arn             = aws_iam_role.flow_log.arn
  log_destination          = aws_cloudwatch_log_group.flow_log.arn
  log_destination_type     = "cloud-watch-logs"
  max_aggregation_interval = 60

  tags = {
    Name = "${local.name}-vpc-flow-log"
  }
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/flow-log/${local.name}"
  retention_in_days = 14

  tags = {
    Name = "${local.name}-vpc-flow-log"
  }
}

resource "aws_iam_role" "flow_log" {
  name_prefix = "${local.name}-flow-log-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${local.name}-flow-log-role"
  }
}

resource "aws_iam_role_policy" "flow_log" {
  name_prefix = "${local.name}-flow-log-"
  role        = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}
