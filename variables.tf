variable "iap_client_id" {
  type        = string
  description = "OAuth2 Client ID for IAP"
}

variable "iap_client_secret" {
  type        = string
  description = "OAuth2 Client Secret for IAP"
  sensitive   = true # Prevents the secret from showing in logs
}