# Terraform Keycloak provider

Use this Terraform configuration to create a Keycloak realm with the [`keycloak/keycloak`](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs) provider. It manages `terraform-org` by default and uses a client secret for OAuth plus mTLS for the HTTPS connection.

## What this config manages

```text
config-as-code/terraform
├── providers.tf   # Keycloak provider with client secret and mTLS
├── variables.tf   # URL, client secret, certificate paths, and realm defaults
└── main.tf        # keycloak_realm.terraform-org
```

Default realm settings:

```hcl
realm_name         = "terraform-org"
realm_display_name = "terraform org"
```

Keep Terraform as the only owner of this realm. Do not also manage `terraform-org` with `keycloak-config-cli`.

## Authentication model

Terraform uses two separate credentials:

- **Client secret** for OAuth client authentication.
- **mTLS client certificate** for the HTTPS connection. Terraform presents `terraform-provider.crt`; Keycloak verifies it chains to `certs/client-ca/client-ca.crt`.

```text
Terraform opens an HTTPS connection to Keycloak's token endpoint
  → Keycloak requests a client certificate during the TLS handshake
  → Terraform presents terraform-provider.crt and proves possession of terraform-provider.key
  → Keycloak verifies the certificate chain with certs/client-ca/client-ca.crt
  → Terraform sends client_id and client_secret to the token endpoint
  → Keycloak issues a client_credentials access token
  → Terraform calls the Admin API with that token
```

The provider also verifies Keycloak's HTTPS server certificate with `certs/server/server-ca.crt`.

## Prerequisites

- Keycloak and Postgres are running from the root Compose stack.
- Local server and client CA files exist. Run `mise run certs` from the repository root if needed.
- Terraform is installed on the host.

## 1. Generate Terraform credentials

Run this from the repository root:

```bash
mise run certs:terraform
```

This creates the mTLS certificate/key used by Terraform:

```text
certs/clients/terraform-provider/terraform-provider.crt  # mTLS client certificate
certs/clients/terraform-provider/terraform-provider.key  # mTLS client private key
```

The mTLS certificate subject defaults to `CN=terraform-provider`, with `extendedKeyUsage=clientAuth`.

## 2. Bootstrap the Keycloak client

Create the provider client once in the `master` realm using the Admin Console. Terraform cannot create this client because it needs the client to authenticate first.

| setting                | value                                            |
| ---------------------- | ------------------------------------------------ |
| Client ID              | `terraform`                                      |
| Client authentication  | `On`                                             |
| Standard flow          | `Off`                                            |
| Direct access grants   | `Off`                                            |
| Service accounts roles | `On`                                             |
| Client Authenticator   | Client Id and Secret                             |
| Client secret          | same value as `client_secret` Terraform variable |

Assign the service account roles required by the provider. Because this example creates realms from the `master` realm, assign the `admin` realm role to the service account in `master`.

In the Admin Console:

```text
master → Clients → terraform → Service account roles → Assign role → Filter by realm roles → admin
```

The upstream provider recommends the `admin` role when managing the entire Keycloak instance. For production, start with this working setup, then reduce permissions once the exact Terraform resource set is known and tested.

## 3. Smoke test token authentication

Use curl to prove both layers work before running Terraform. This sends the client secret over mTLS.

```bash
TOKEN_URL="https://localhost:8443/realms/master/protocol/openid-connect/token"
CLIENT_ID="terraform"
CLIENT_SECRET="changeit"

curl --cert certs/clients/terraform-provider/terraform-provider.crt \
  --key certs/clients/terraform-provider/terraform-provider.key \
  --cacert certs/server/server-ca.crt \
  -d grant_type=client_credentials \
  -d client_id="$CLIENT_ID" \
  -d client_secret="$CLIENT_SECRET" \
  "$TOKEN_URL"
```

## 4. Apply Terraform

Run Terraform with the project mise tasks from the repository root:

```bash
mise run terraform:init
mise run terraform:plan
mise run terraform:apply
```

Or run Terraform directly from this directory:

```bash
cd config-as-code/terraform
terraform init
terraform plan
terraform apply
```

After apply, Keycloak should contain an enabled realm named `terraform-org`.

## Configure a different realm

Override defaults with `-var` flags:

```bash
terraform apply \
  -var 'realm_name=example-org' \
  -var 'realm_display_name=example org'
```

Or create `terraform.tfvars` in this directory:

```hcl
realm_name         = "example-org"
realm_display_name = "example org"
```

## Provider inputs

| variable                      | default                                                         |
| ----------------------------- | --------------------------------------------------------------- |
| `keycloak_url`                | `https://localhost:8443`                                        |
| `login_realm`                 | `master`                                                        |
| `client_id`                   | `terraform`                                                     |
| `client_secret`               | `changeit`                                                      |
| `tls_client_certificate_path` | `../../certs/clients/terraform-provider/terraform-provider.crt` |
| `tls_client_private_key_path` | `../../certs/clients/terraform-provider/terraform-provider.key` |
| `root_ca_certificate_path`    | `../../certs/server/server-ca.crt`                              |
| `realm_name`                  | `terraform-org`                                                 |
| `realm_display_name`          | `terraform org`                                                 |
