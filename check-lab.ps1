# 1. Check GCP BGP Status
Write-Host "Checking GCP BGP Peering..." -ForegroundColor Cyan
gcloud compute routers get-status gcp-to-aws-router --region australia-southeast1 --format="table(result.bgpPeerStatus[0].name, result.bgpPeerStatus[0].state, result.bgpPeerStatus[0].status)"

# 2. Check AWS VPN Status
Write-Host "`nChecking AWS VPN Tunnel Status..." -ForegroundColor Cyan
aws ec2 describe-vpn-connections --query "VpnConnections[*].VgwTelemetry[*].{Status:Status,OutsideIp:OutsideIpAddress}" --output table

# 3. Check Routes Learned
Write-Host "`nChecking if GCP learned the AWS 172.16.x.x route..." -ForegroundColor Cyan
gcloud compute routers get-status gcp-to-aws-router --region australia-southeast1 --format="value(result.bestRoutesForRouter)"