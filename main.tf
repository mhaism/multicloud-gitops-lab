# --- 1. PROVIDERS ---
provider "aws" {
  region = "ap-southeast-2"
}

# --- 2. PALO ALTO DATA SOURCE ---
# (Ensure your data source for panos_image is defined elsewhere or here)

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

  # FIXED: Metadata moved here (Direct child of google_compute_instance)
    metadata = {
    serial-port-enable  = "TRUE"   # <--- Ensure this is TRUE
    mgmt-interface-swap = "enable"
    serial-port-enable  = "TRUE"
    startup-script      = "set mgt-config users admin password TemporaryPassword123!"
	admin-password      = "TemporaryPassword123!" # Use this specific key
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.panos_image.self_link
      type  = "pd-ssd"
      size  = 60
    }
  }

  # NIC 0: Management
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
    scopes = ["cloud-platform"]
  }
}

output "firewall_management_url" {
  value = "https://${google_compute_instance.pan_fw.network_interface[0].access_config[0].nat_ip}"
}

resource "google_compute_router" "gcp_router" {
  name    = "gcp-to-aws-router"
  network = google_compute_network.vpc_network_gcp.name
  region  = "australia-southeast1"
  bgp {
    asn = 65001
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
  cidr_block        = "172.16.10.0/24"
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
  tags       = { Name = "cgw-gcp-int0" }
}

resource "aws_customer_gateway" "cgw1" {
  bgp_asn    = 65001
  ip_address = google_compute_ha_vpn_gateway.ha_gateway.vpn_interfaces[1].ip_address
  type       = "ipsec.1"
  tags       = { Name = "cgw-gcp-int1" }
}

# --- AWS VPN CONNECTION TO TRANSIT GATEWAY ---
resource "aws_vpn_connection" "vpn_to_gcp" {
  customer_gateway_id = aws_customer_gateway.cgw0.id
  transit_gateway_id  = aws_ec2_transit_gateway.aws_tgw.id
  type                = "ipsec.1"
  static_routes_only  = false 
  tags                = { Name = "aws-to-gcp-vpn" }
}

# --- GCP VPN TUNNELS ---
resource "google_compute_vpn_tunnel" "tunnel0" {
  name                            = "gcp-to-aws-tunnel0"
  region                          = "australia-southeast1"
  vpn_gateway                     = google_compute_ha_vpn_gateway.ha_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_gateway.id
  peer_external_gateway_interface = 0
  shared_secret                   = aws_vpn_connection.vpn_to_gcp.tunnel1_preshared_key
  router                          = google_compute_router.gcp_router.name
  vpn_gateway_interface           = 0
}

# --- GCP ROUTER INTERFACE ---
resource "google_compute_router_interface" "iface0" {
  name       = "iface-vpn-0"
  router     = google_compute_router.gcp_router.name
  region     = "australia-southeast1"
  ip_range   = "${aws_vpn_connection.vpn_to_gcp.tunnel1_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunnel0.name
}

# --- GCP BGP PEER ---
resource "google_compute_router_peer" "peer0" {
  name                      = "peer-aws-0"
  router                    = google_compute_router.gcp_router.name
  region                    = "australia-southeast1"
  peer_ip_address           = aws_vpn_connection.vpn_to_gcp.tunnel1_vgw_inside_address
  peer_asn                  = 65002
  interface                 = google_compute_router_interface.iface0.name
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