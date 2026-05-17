variable "keycloak_url" {
  description = "Base URL for Keycloak. Use https://localhost:8443 when running Terraform on the host."
  type        = string
  default     = "https://localhost:8443"
}

variable "login_realm" {
  description = "Realm where the Terraform provider client authenticates."
  type        = string
  default     = "master"
}

variable "client_id" {
  description = "OIDC client ID used by the Terraform provider."
  type        = string
  default     = "terraform"
}

variable "client_secret" {
  description = "OIDC client secret used by the Terraform provider."
  type        = string
  default     = "changeit"
  sensitive   = true
}

variable "tls_client_certificate_path" {
  description = "PEM client certificate presented by Terraform for TLS mTLS."
  type        = string
  default     = "../../certs/clients/terraform-provider/terraform-provider.crt"
}

variable "tls_client_private_key_path" {
  description = "PEM private key for tls_client_certificate_path."
  type        = string
  default     = "../../certs/clients/terraform-provider/terraform-provider.key"
  sensitive   = true
}

variable "root_ca_certificate_path" {
  description = "CA certificate used to verify Keycloak's HTTPS server certificate."
  type        = string
  default     = "../../certs/server/server-ca.crt"
}

variable "realm_name" {
  description = "Realm managed by this Terraform configuration."
  type        = string
  default     = "terraform-org"
}

variable "realm_display_name" {
  description = "Display name for the Terraform-managed realm."
  type        = string
  default     = "terraform org"
}
