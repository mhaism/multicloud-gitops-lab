# =============================================================================
# 1. TERRAFORM CONFIGURATION & PROVIDER
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
    bucket = "project-5eb321fb-28e4-488a-82a-tfstate"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = "project-5eb321fb-28e4-488a-82a"
  region  = "australia-southeast1" # Sydney-based context
}

# =============================================================================
# 2. APIS & IDENTITY (Zero-Trust Enablement)
# =============================================================================

# Enable necessary APIs for Serverless and Identity
resource "google_project_service" "enabled_apis" {
  for_each = toset([
    "run.googleapis.com",
    "iap.googleapis.com",
    "compute.googleapis.com" # Required for Load Balancing
  ])
  service            = each.key
  disable_on_destroy = false
}

# Create a scoped Service Account for the application
resource "google_service_account" "serverless_identity" {
  account_id   = "serverless-lab-sa"
  display_name = "Identity for Cloud Run Lab"
}

# =============================================================================
# 3. SERVERLESS WORKLOAD (Cloud Run)
# =============================================================================

resource "google_cloud_run_v2_service" "identity_app" {
  name     = "identity-lab-app"
  location = "australia-southeast1"
  ingress  = "INGRESS_TRAFFIC_ALL" # Using IAP at the app layer

  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
    service_account = google_service_account.serverless_identity.email
  }

  depends_on = [google_project_service.enabled_apis]
}

# =============================================================================
# 4. IDENTITY-BASED ACCESS (The Audit Fix)
# =============================================================================

# REMOVED: allUsers (Public access is a compliance failure)
# ADDED: Explicit Identity-Aware Proxy permission 
resource "google_cloud_run_v2_service_iam_member" "iap_authorized_user" {
  name     = google_cloud_run_v2_service.identity_app.name
  location = google_cloud_run_v2_service.identity_app.location
  role     = "roles/run.invoker"
  member   = "user:your-email@example.com" # Replace with your Australian lab email
}

# =============================================================================
# 5. OUTPUTS
# =============================================================================
output "app_url" {
  value = google_cloud_run_v2_service.identity_app.uri
}