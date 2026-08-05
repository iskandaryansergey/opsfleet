variable "project_name" {
  description = "Name of the project, used as prefix for resource naming"
  type        = string
  default     = "opsfleet"
}

variable "environment" {
  description = "Deployment environment identifier"
  type        = string
  default     = "poc"
}

variable "region" {
  description = "AWS region for the state backend resources"
  type        = string
  default     = "us-east-1"
}
