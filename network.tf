# network.tf

# 1. Management Network
resource "google_compute_network" "mgmt_vpc" {
  name                    = "pan-mgmt-vpc"
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "mgmt_subnet" {
  name          = "pan-mgmt-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "australia-southeast1" # <--- Add this
  network       = google_compute_network.mgmt_vpc.id
}

# 2. Untrust (Internet) Network
resource "google_compute_network" "untrust_vpc" {
  name                    = "pan-untrust-vpc"
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "untrust_subnet" {
  name          = "pan-untrust-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = "australia-southeast1" # <--- Add this
  network       = google_compute_network.untrust_vpc.id
}

# 3. Trust (Internal) Network
resource "google_compute_network" "trust_vpc" {
  name                    = "pan-trust-vpc"
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "trust_subnet" {
  name          = "pan-trust-subnet"
  ip_cidr_range = "10.0.3.0/24"
  region        = "australia-southeast1" # <--- Add this
  network       = google_compute_network.trust_vpc.id
}

# 4. Security Rule: Allow you to manage the firewall
resource "google_compute_firewall" "allow_mgmt" {
  name    = "allow-mgmt"
  network = google_compute_network.mgmt_vpc.name
  allow {
    protocol = "tcp"
    ports    = ["443", "22"]
  }
  # Update this line
  source_ranges = ["0.0.0.0/0"] # <--- CHANGE THIS! (e.g., "203.0.113.50/32")
}