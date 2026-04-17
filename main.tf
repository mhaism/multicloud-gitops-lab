# =============================================================================
# 1. TERRAFORM CONFIGURATION (The "Zero-Trust" Control Plane)
# =============================================================================
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0" 
    }
  }

  # Keyless state storage using the GCS bucket you created
  backend "gcs" {
    bucket  = "project-5eb321fb-28e4-488a-82a-tfstate" 
    prefix  = "terraform/state"
  }
}

# =============================================================================
# 2. PROVIDER SETUP
# =============================================================================
provider "google" {
  project = "project-5eb321fb-28e4-488a-82a"
  region  = "australia-southeast1" # Sydney
}

# =============================================================================
# 3. IDENTITY & APIS
# =============================================================================

# Enable the Cloud Run API (Service-level permission)
resource "google_project_service" "run_api" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

# Create a scoped Service Account for the application
resource "google_service_account" "serverless_identity" {
  account_id   = "serverless-lab-sa"
  display_name = "Identity for Cloud Run Lab"
}

# =============================================================================
# 4. SERVERLESS DATA PLANE (The "Workload")
# =============================================================================

# Deploy the Cloud Run Service to Sydney
resource "google_cloud_run_v2_service" "identity_app" {
  name     = "identity-lab-app"
  location = "australia-southeast1"
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello" 
    }
    # Bind the workload to our specific Service Account
    service_account = google_service_account.serverless_identity.email
  }

  depends_on = [google_project_service.run_api]
}

# Allow Public Access (Verification endpoint)
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  name     = google_cloud_run_v2_service.identity_app.name
  location = google_cloud_run_v2_service.identity_app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# 5. OUTPUTS
# =============================================================================
output "app_url" {
  value = google_cloud_run_v2_service.identity_app.uri
}