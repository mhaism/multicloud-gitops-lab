# --- 1. PROVIDERS ---
provider "aws" {
  region = "ap-southeast-2"
}

provider "google" {
  project = "your-gcp-project-id" # Ensure this matches your project
  region  = "australia-southeast1"
}

# --- 2. PALO ALTO DATA SOURCE ---
data "google_compute_image" "panos_image" {
  project = "paloaltonetworksgcp-public"
  family  = "vmseries-flex-byol-1102" # Using the image family from your logs
}

# --- 3. GCP INFRASTRUCTURE ---
resource "google_compute_network" "vpc_network_gcp" {
  name                    = "gcp-prod-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_instance" "pan_fw" {
  name           = "pan-fw-01"
  machine_type   = "e2-standard-4"
  zone           = "australia-southeast1-a" 
  can_ip_forward = true 

  metadata = {
    serial-port-enable  = "TRUE"   
    mgmt-interface-swap = "enable" 
    # Primary key for bootstrap credentialing
    admin-password      = "TemporaryPassword123!" 
    # Fallback script for initial setup
    startup-script      = "set mgt-config users admin password TemporaryPassword123!"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.panos_image.self_link
      type  = "pd-ssd"
      size  = 100 # Increased to 100GB for PAN-OS 11 stability
    }
  }

  # NIC 0: Management (Maps the External IP to the MGMT interface) [cite: 12]
  network_interface {
    subnetwork = google_compute_subnetwork.mgmt_subnet.id 
    access_config {}
  }

  # NIC 1: Untrust
  network_interface {
    subnetwork = google_compute_subnetwork.untrust_subnet.id
  }

  # NIC 2: Trust
  network_interface {
    subnetwork = google_compute_subnetwork.trust_subnet.id
  }

  service_account {
    scopes = ["cloud-platform"] [cite: 4]
  }
}

# --- 4. AWS INFRASTRUCTURE ---
resource "aws_vpc" "aws_prod_vpc" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "aws-prod-vpc" }
}

resource "aws_subnet" "aws_mgmt_sub" {
  vpc_id            = aws_vpc.aws_prod_vpc.id
  cidr_block        = "172.16.10.0/24" [cite: 5]
  availability_zone = "ap-southeast-2a"
  tags = { Name = "aws-mgmt-sub" }
}

# --- 5. THE ROUTING BRIDGE ---
resource "aws_ec2_transit_gateway" "aws_tgw" {
  description     = "Main Multicloud Hub"
  amazon_side_asn = 65002
}

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw_attach" {
  subnet_ids         = [aws_subnet.aws_mgmt_sub.id]
  transit_gateway_id = aws_ec2_transit_gateway.aws_tgw.id
  vpc_id             = aws_vpc.aws_prod_vpc.id
}

# --- GCP HA VPN GATEWAY ---
resource "google_compute_ha_vpn_gateway" "ha_gateway" {
  name    = "gcp-to-aws-ha-vpn"
  network = google_compute_network.vpc_network_gcp.id
  region  = "australia-southeast1"
}

# --- AWS CUSTOMER GATEWAY (Points to GCP) ---
resource "aws_customer_gateway" "cgw0" {
  bgp_asn    = 65001
  ip_address = google_compute_ha_vpn_gateway.ha_gateway.vpn_interfaces[0].ip_address
  type       = "ipsec.1"
  tags       = { Name = "cgw-gcp-int0" } [cite: 6]
}

# --- AWS VPN CONNECTION TO TRANSIT GATEWAY ---
resource "aws_vpn_connection" "vpn_to_gcp" {
  customer_gateway_id = aws_customer_gateway.cgw0.id
  transit_gateway_id  = aws_ec2_transit_gateway.aws_tgw.id [cite: 7]
  type                = "ipsec.1"
  static_routes_only  = false 
  tags                = { Name = "aws-to-gcp-vpn" }
}

# --- GCP VPN TUNNEL ---
resource "google_compute_vpn_tunnel" "tunnel0" {
  name                            = "gcp-to-aws-tunnel0"
  region                          = "australia-southeast1" [cite: 8]
  vpn_gateway                     = google_compute_ha_vpn_gateway.ha_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_gateway.id
  peer_external_gateway_interface = 0
  shared_secret                   = aws_vpn_connection.vpn_to_gcp.tunnel1_preshared_key
  router                          = google_compute_router.gcp_router.name [cite: 9]
  vpn_gateway_interface           = 0
}

# --- GCP ROUTER & BGP ---
resource "google_compute_router" "gcp_router" {
  name    = "gcp-to-aws-router"
  network = google_compute_network.vpc_network_gcp.name
  region  = "australia-southeast1"
  bgp {
    asn = 65001
  }
}

resource "google_compute_router_interface" "iface0" {
  name       = "iface-vpn-0"
  router     = google_compute_router.gcp_router.name
  region     = "australia-southeast1"
  ip_range   = "${aws_vpn_connection.vpn_to_gcp.tunnel1_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunnel0.name
}

resource "google_compute_router_peer" "peer0" {
  name                      = "peer-aws-0" [cite: 10]
  router                    = google_compute_router.gcp_router.name
  region                    = "australia-southeast1"
  peer_ip_address           = aws_vpn_connection.vpn_to_gcp.tunnel1_vgw_inside_address
  peer_asn                  = 65002
  interface                 = google_compute_router_interface.iface0.name [cite: 11]
  advertised_route_priority = 100
}

# --- GCP EXTERNAL GATEWAY ---
resource "google_compute_external_vpn_gateway" "aws_gateway" {
  name            = "aws-side-gateway"
  redundancy_type = "TWO_IPS_REDUNDANCY"

  interface {
    id         = 0
    ip_address = aws_vpn_connection.vpn_to_gcp.tunnel1_address
  }

  interface {
    id         = 1
    ip_address = aws_vpn_connection.vpn_to_gcp.tunnel2_address
  }
}
# --- OUTPUTS ---
output "firewall_public_ip" {
  value = google_compute_instance.pan_fw.network_interface[0].access_config[0].nat_ip
}
