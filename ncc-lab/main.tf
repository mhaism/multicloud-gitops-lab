# main.tf

provider "google" {
  project = "project-5eb321fb-28e4-488a-82a" # <--- CHANGE THIS
  region  = "us-central1"
  zone    = "us-central1-a"
}

# ------------------------------------------------------------------------------
# 1. THE NETWORKS (The Spokes)
# ------------------------------------------------------------------------------
resource "google_compute_network" "vpc_a" {
  name                    = "vpc-a"
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "subnet_a" {
  name          = "subnet-a"
  ip_cidr_range = "10.1.0.0/24"
  network       = google_compute_network.vpc_a.id
}

resource "google_compute_network" "vpc_b" {
  name                    = "vpc-b"
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "subnet_b" {
  name          = "subnet-b"
  ip_cidr_range = "10.2.0.0/24"
  network       = google_compute_network.vpc_b.id
}

# ------------------------------------------------------------------------------
# 2. NETWORK CONNECTIVITY CENTER (The Hub)
# ------------------------------------------------------------------------------
# Create the Hub
resource "google_network_connectivity_hub" "main_hub" {
  name        = "my-enterprise-hub"
  description = "Central routing hub for the lab"
}

# Attach VPC A as a Spoke
resource "google_network_connectivity_spoke" "spoke_vpc_a" {
  name     = "spoke-vpc-a"
  location = "global" # VPC spokes must be global
  hub      = google_network_connectivity_hub.main_hub.id

  linked_vpc_network {
    uri = google_compute_network.vpc_a.self_link
  }
}

# Attach VPC B as a Spoke
resource "google_network_connectivity_spoke" "spoke_vpc_b" {
  name     = "spoke-vpc-b"
  location = "global"
  hub      = google_network_connectivity_hub.main_hub.id

  linked_vpc_network {
    uri = google_compute_network.vpc_b.self_link
  }
}

# ------------------------------------------------------------------------------
# 3. FIREWALLS & TEST VMS

# Allow ping and SSH internally so we can test the connection
resource "google_compute_firewall" "allow_internal_a" {
  name    = "allow-internal-a"
  network = google_compute_network.vpc_a.name
  
  allow {
    protocol = "icmp"
  }
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["10.0.0.0/8", "35.235.240.0/20"]
}

resource "google_compute_firewall" "allow_internal_b" {
  name    = "allow-internal-b"
  network = google_compute_network.vpc_b.name
  
  allow {
    protocol = "icmp"
  }
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["10.0.0.0/8", "35.235.240.0/20"]
}

# VM in VPC A
resource "google_compute_instance" "vm_a" {
  name         = "test-vm-a"
  machine_type = "e2-micro"
  
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.subnet_a.id
  }
}

# VM in VPC B
resource "google_compute_instance" "vm_b" {
  name         = "test-vm-b"
  machine_type = "e2-micro"
  
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.subnet_b.id
  }
}

# Print the internal IPs so you know what to ping
output "vm_a_internal_ip" {
  value = google_compute_instance.vm_a.network_interface[0].network_ip
}

output "vm_b_internal_ip" {
  value = google_compute_instance.vm_b.network_interface[0].network_ip
}