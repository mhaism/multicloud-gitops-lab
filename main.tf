# 1. NEW: Move the state file from AWS S3 to Google Cloud Storage
terraform {
  backend "gcs" {
    bucket  = "project-5eb321fb-28e4-488a-82a-tfstate" 
    prefix  = "terraform/state"
  }
}

# 2. Provide the GCP Provider using WIF
provider "google" {
  project = "project-5eb321fb-28e4-488a-82a"
  region  = "australia-southeast1"
}

# 3. Create a simple "Identity-Verified" Network
resource "google_compute_network" "identity_lab_vpc" {
  name                    = "identity-lab-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "lab_subnet" {
  name          = "lab-subnet-sydney"
  ip_cidr_range = "10.0.10.0/24"
  region        = "australia-southeast1"
  network       = google_compute_network.identity_lab_vpc.id
}

# 4. Output the result to prove success
output "vpc_status" {
  value = "Deployment successful via GitHub WIF!"
}