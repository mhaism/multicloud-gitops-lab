terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"
}
# 1. Reference the existing user you created in the console
data "aws_iam_user" "admin_user" {
  user_name = "Terraform-Admin"
}

# 2. Attach the AdministratorAccess managed policy to that user
resource "aws_iam_user_policy_attachment" "admin_attach" {
  user       = data.aws_iam_user.admin_user.user_name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}