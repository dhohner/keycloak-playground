output "realm" {
  description = "Terraform-managed realm name."
  value       = keycloak_realm.realm.realm
}
