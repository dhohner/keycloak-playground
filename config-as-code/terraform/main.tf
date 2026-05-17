resource "keycloak_realm" "realm" {
  realm        = var.realm_name
  display_name = var.realm_display_name
  enabled      = true
}
