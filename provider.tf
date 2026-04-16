# provider.tf
terraform {
  required_version = ">= 1.5.0" # Fixes Warning 1
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # Bump to v6.x to match your lock file
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0" # Bump to v7.x to fix the GCP error
    }
  }

 backend "s3" {
    bucket         = "miraj-tf-state-vault-8a2b"
    key            = "multicloud-lab/terraform.tfstate"
    region         = "ap-southeast-2" # Back to Sydney!
    encrypt        = true
    use_lockfile   = true
  }
}
provider "google" {
  project = "project-5eb321fb-28e4-488a-82a" # 
  region  = "australia-southeast1"
 
}

# This fetches the latest Palo Alto PAN-OS image automatically
data "google_compute_image" "panos_image" {
  name  = "vmseries-flex-byol-1102" 
  project = "paloaltonetworksgcp-public"
}