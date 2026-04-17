# =============================================================================
# SERVERLESS IDENTITY LAB (Sydney - australia-southeast1)
# =============================================================================

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0" 
    }
  }
  backend "gcs" {
    bucket  = "project-5eb321fb-28e4-488a-82a-tfstate" 
    prefix  = "terraform/state"
  }
}

provider "google" {
  project = "project-5eb321fb-28e4-488a-82a"
  region  = "australia-southeast1" 
}

# 1. ENABLE APIS
resource "google_project_service" "enabled_apis" {
  for_each = toset(["run.googleapis.com", "iap.googleapis.com"])
  service            = each.key
  disable_on_destroy = false
}

# 2. CLOUD RUN SERVICE
resource "google_cloud_run_v2_service" "identity_app" {
  name     = "identity-lab-app"
  location = "australia-southeast1"
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello" 
    }
    # Identity for the workload
    service_account = "serverless-lab-sa@project-5eb321fb-28e4-488a-82a.iam.gserviceaccount.com"
  }
  depends_on = [google_project_service.enabled_apis]
}

# 3. IDENTITY-BASED PERMISSIONS (Audit Fix: No more allUsers)
resource "google_cloud_run_v2_service_iam_member" "authorized_user" {
  name     = google_cloud_run_v2_service.identity_app.name
  location = google_cloud_run_v2_service.identity_app.location
  role     = "roles/run.invoker"
  member   = "user:your-email@example.com" # Replace with your Australian lab email
}