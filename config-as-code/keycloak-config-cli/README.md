# keycloak-config-cli

Imports Keycloak realm configuration from YAML files using the [adorsys keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli).

Current import:

```text
config-as-code/keycloak-config-cli/realms/acme-org.yaml
```

Creates realm `acme-org` (display name: _acme org_).

## Authentication model

The CLI authenticates to Keycloak using OAuth `client_credentials` with a client secret.

```text
grant_type=client_credentials
client_id=keycloak-config-cli
client_secret=<KEYCLOAK_CONFIG_CLI_CLIENT_SECRET>
```

Certificate-based OAuth client authentication is not used. The CLI connects over HTTPS and verifies Keycloak's server certificate via a Java truststore — TLS is verified, but the certificate is not used as the OAuth credential.

## How to: Bootstrap the Keycloak client

Before the CLI can import anything, create an OIDC client in the `master` realm via the Admin Console.

| setting                | value                                                       |
| ---------------------- | ----------------------------------------------------------- |
| Client ID              | `keycloak-config-cli`                                       |
| Client authentication  | `On`                                                        |
| Standard flow          | `Off`                                                       |
| Direct access grants   | `Off`                                                       |
| Service accounts roles | `On`                                                        |
| Client Authenticator   | Client Id and Secret                                        |
| Client secret          | same value as `KEYCLOAK_CONFIG_CLI_CLIENT_SECRET` in `.env` |

Assign service account roles that allow realm management. For full realm creation and update, assign roles from the `realm-management` client (e.g. `manage-realm`, `manage-clients`). Reduce permissions once your import scope is known.

## How to: Create the truststore

The CLI runs in a container and must trust Keycloak's HTTPS server certificate. Import the server CA (`server-ca.crt`), not the leaf cert (`tls.crt`), to avoid Java `PKIX path building failed` errors.

```bash
mkdir -p certs/config-cli
rm -f certs/config-cli/keycloak-truststore.p12

keytool -importcert -noprompt \
  -alias keycloak-server-ca \
  -file certs/server/server-ca.crt \
  -keystore certs/config-cli/keycloak-truststore.p12 \
  -storetype PKCS12 \
  -storepass changeit
```

## How to: Run the import

Run the CLI as a one-shot Compose container. From the project root:

```bash
scripts/compose.sh config-apply
```

Enable action/component debug logs for a single run:

```bash
scripts/compose.sh config-apply --debug
# or
KEYCLOAK_CONFIG_CLI_COMPONENT_LOG_LEVEL=debug scripts/compose.sh config-apply
# direct container env also works:
LOGGING_LEVEL_KEYCLOAKCONFIGCLI=debug scripts/compose.sh config-apply
```

The container exits after the import completes and is removed. For troubleshooting, run it without `--rm` using raw Compose args, then inspect logs:

```bash
scripts/compose.sh --config-cli up keycloak-config-cli
scripts/compose.sh config-logs
```

## Reference: Compose configuration

### Environment variables

| variable                                  | default               | description                           |
| ----------------------------------------- | --------------------- | ------------------------------------- |
| `KEYCLOAK_CONFIG_CLI_LOGIN_REALM`         | `master`              | realm the CLI authenticates against   |
| `KEYCLOAK_CONFIG_CLI_CLIENT_ID`           | `keycloak-config-cli` | OIDC client ID                        |
| `KEYCLOAK_CONFIG_CLI_CLIENT_SECRET`       | `changeit`            | client secret                         |
| `KEYCLOAK_CONFIG_CLI_TRUSTSTORE_PASSWORD` | `changeit`            | password for the server CA truststore |
| `KEYCLOAK_CONFIG_CLI_DEBUG`               | `false`               | Spring Boot debug mode                |
| `KEYCLOAK_CONFIG_CLI_LOG_LEVEL`           | `info`                | root logging level (`debug`, `info`)  |
| `KEYCLOAK_CONFIG_CLI_COMPONENT_LOG_LEVEL` | `info`                | `de.adorsys.keycloak.config` component/action logs |
| `KEYCLOAK_CONFIG_CLI_HTTP_LOG_LEVEL`      | `info`                | HTTP request logs to Keycloak         |
| `KEYCLOAK_CONFIG_CLI_REALM_CONFIG_LOG_LEVEL` | `info`             | realm config logs; `trace` may expose sensitive data |

`KEYCLOAK_URL` is hardcoded to `https://keycloak:8443`. The CLI joins the external Compose network `keycloak-playground`, where `keycloak` resolves to the Keycloak service/container. Keycloak's server certificate must include `DNS:keycloak` as a SAN.

### Volume mounts

| host path                                   | container path                         | purpose                             |
| ------------------------------------------- | -------------------------------------- | ----------------------------------- |
| `config-as-code/keycloak-config-cli/realms` | `/config`                              | YAML realm files to import          |
| `certs/config-cli/keycloak-truststore.p12`  | `/certs/trust/keycloak-truststore.p12` | truststore for Keycloak's server CA |
