# main.tf

provider "google" {
  project = "project-5eb321fb-28e4-488a-82a" # <--- CHANGE THIS
  region  = "us-central1"
  zone    = "us-central1-a"
}

# ------------------------------------------------------------------------------
# 1. NETWORKS & SUBNETS
# ------------------------------------------------------------------------------
resource "google_compute_network" "swp_vpc" {
  name                    = "swp-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vm_subnet" {
  name          = "swp-vm-subnet"
  ip_cidr_range = "10.5.0.0/24"
  region        = "us-central1"
  network       = google_compute_network.swp_vpc.id
}

resource "google_compute_subnetwork" "proxy_subnet" {
  name          = "swp-proxy-subnet"
  ip_cidr_range = "10.129.0.0/23"
  region        = "us-central1"
  network       = google_compute_network.swp_vpc.id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# FIX 1: The name perfectly matches the gateway name
resource "google_compute_address" "swp_ip" {
  name         = "my-swp-gateway" 
  subnetwork   = google_compute_subnetwork.vm_subnet.id
  address_type = "INTERNAL"
  region       = "us-central1"
}

# ------------------------------------------------------------------------------
# 2. SECURE WEB PROXY POLICIES
# ------------------------------------------------------------------------------
resource "google_network_security_gateway_security_policy" "swp_policy" {
  name     = "my-swp-policy"
  location = "us-central1"
}

resource "google_network_security_gateway_security_policy_rule" "allow_github" {
  name                    = "allow-github"
  gateway_security_policy = google_network_security_gateway_security_policy.swp_policy.name
  location                = "us-central1"
  enabled                 = true
  priority                = 100
  session_matcher         = "host() == 'github.com'"
  basic_profile           = "ALLOW"
}

# ------------------------------------------------------------------------------
# 3. THE PROXY GATEWAY
# ------------------------------------------------------------------------------
resource "google_network_services_gateway" "swp_gateway" {
  name                                 = "my-swp-gateway"
  location                             = "us-central1"
  type                                 = "SECURE_WEB_GATEWAY"
  ports                                = [443]
  network                              = google_compute_network.swp_vpc.id
  subnetwork                           = google_compute_subnetwork.vm_subnet.id
  addresses                            = [google_compute_address.swp_ip.address] # FIX 2: Uses .address instead of .id
  gateway_security_policy              = google_network_security_gateway_security_policy.swp_policy.id
}

# ------------------------------------------------------------------------------
# 4. TEST VM & FIREWALLS
# ------------------------------------------------------------------------------
# FIX 3: Expanded multi-line syntax for the firewall
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "swp-allow-ssh"
  network = google_compute_network.swp_vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["35.235.240.0/20"] 
}

resource "google_compute_instance" "test_vm" {
  name         = "swp-test-vm"
  machine_type = "e2-micro"
  
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.vm_subnet.id
  }
}

output "proxy_ip" {
  value = google_compute_address.swp_ip.address
}