provider "keycloak" {
  url       = var.keycloak_url
  realm     = var.login_realm
  client_id = var.client_id

  # OAuth client authentication uses a client secret for now.
  client_secret = var.client_secret

  # The Keycloak Terraform provider also presents this certificate/key for TLS
  # mTLS. This is transport authentication, separate from the OAuth client secret.
  tls_client_certificate = file(var.tls_client_certificate_path)
  tls_client_private_key = file(var.tls_client_private_key_path)

  # Trust the local Keycloak HTTPS server certificate chain.
  root_ca_certificate = file(var.root_ca_certificate_path)
}
