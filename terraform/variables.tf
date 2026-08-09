variable "project_name" {
  description = "Name of the project, used as prefix for resource naming"
  type        = string
  default     = "opsfleet"
}

variable "environment" {
  description = "Deployment environment identifier (e.g. poc, staging, production)"
  type        = string
  default     = "poc"

  validation {
    condition     = contains(["poc", "staging", "production"], var.environment)
    error_message = "Environment must be one of: poc, staging, production."
  }
}

variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "opsfleet-eks"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "Primary CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "pod_cidr" {
  description = "Secondary CIDR block for pod networking (custom networking)"
  type        = string
  default     = "100.64.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "Pod CIDR must be a valid IPv4 CIDR block."
  }
}

variable "enable_nat_gateway" {
  description = "Whether to provision NAT gateways for private subnet internet access"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway for all AZs (cost optimization for non-production)"
  type        = bool
  default     = true
}

variable "system_node_instance_types" {
  description = "EC2 instance types for the system managed node group"
  type        = list(string)
  default     = ["t3.small"]
}

variable "system_node_min_size" {
  description = "Minimum number of nodes in the system node group"
  type        = number
  default     = 2

  validation {
    condition     = var.system_node_min_size >= 1
    error_message = "Minimum node size must be at least 1."
  }
}

variable "system_node_max_size" {
  description = "Maximum number of nodes in the system node group"
  type        = number
  default     = 3

  validation {
    condition     = var.system_node_max_size >= 1
    error_message = "Maximum node size must be at least 1."
  }
}

variable "system_node_desired_size" {
  description = "Desired number of nodes in the system node group"
  type        = number
  default     = 2

  validation {
    condition     = var.system_node_desired_size >= 1
    error_message = "Desired node size must be at least 1."
  }
}

variable "karpenter_version" {
  description = "Version of the Karpenter Helm chart to deploy"
  type        = string
  default     = "1.14.0"
}

variable "enable_monitoring" {
  description = "Whether to create CloudWatch alarms and dashboards"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications (leave empty to skip)"
  type        = string
  default     = ""
}

variable "monthly_budget_amount" {
  description = "Monthly AWS budget limit in USD"
  type        = string
  default     = "50"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
