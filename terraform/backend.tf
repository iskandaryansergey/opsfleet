terraform {
  backend "s3" {
    bucket         = "opsfleet-terraform-state-346607799227"
    key            = "eks-cluster/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "opsfleet-terraform-locks"
  }
}
