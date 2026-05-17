# Keycloak Playground

A local [Keycloak 26.6.1](https://www.keycloak.org/) development environment with:

- PostgreSQL backing database
- HTTPS on port `8443`
- mTLS-ready inbound client certificate validation
- Optional config-as-code realm imports

This repository is for learning and local experiments. Defaults are intentionally dev-friendly.

## Mental model

```text
browser / API client  ──HTTPS──────────────────────▶ Keycloak ──▶ Postgres
machine client        ──HTTPS + client cert─────────▶ Keycloak token endpoint
config-as-code tool   ──HTTPS + client secret───────▶ Keycloak Admin API
```

| concept              | meaning                                                                |
| -------------------- | ---------------------------------------------------------------------- |
| HTTPS server cert    | cert Keycloak presents to clients so they can trust Keycloak           |
| client cert          | cert a caller presents to Keycloak to prove machine identity           |
| client CA            | CA Keycloak trusts when validating client certs                        |
| truststore           | file containing trusted certificates or CAs                            |
| keystore             | file containing a private key and its certificate                      |
| `client_credentials` | OAuth grant for machine-to-machine tokens; no user or browser involved |

## Stack

| component | image                              | port                            |
| --------- | ---------------------------------- | ------------------------------- |
| Keycloak  | `quay.io/keycloak/keycloak:26.6.1` | `8443` (HTTPS), `9000` (health) |
| Postgres  | `postgres:17-alpine`               | `5432`                          |

No custom Keycloak image is used.

## Quick start

**Prerequisites:** Docker or Podman with Compose support. Optional: [mise](https://mise.jdx.dev/) for task shortcuts.

1. Copy the environment file.

```bash
cp .env.example .env
```

2. Generate certificates — see [Generate local dev certs](#generate-local-dev-certs).

```bash
mise run certs
```

3. Start the stack.

```bash
mise run start
mise run logs

# Without mise
scripts/compose.sh start
scripts/compose.sh logs
```

4. Open the admin UI at `https://localhost:8443`.

Default credentials: `admin` / `admin`

**Reset the local database:**

```bash
docker compose down -v

# Podman
podman-compose down -v
```

## Required files

Keycloak will not start without these files:

```text
certs/server/tls.crt
certs/server/tls.key
certs/client-ca/client-truststore.p12
```

Optional — add trusted CAs for Keycloak outbound HTTPS:

```text
certs/internal-ca/*.crt
certs/internal-ca/*.pem
```

## Mise tasks

This repo includes `.mise.toml` tasks for common setup and operations.

```bash
mise run help
```

| task                              | purpose                                                         |
| --------------------------------- | --------------------------------------------------------------- |
| `help`                            | show available mise tasks                                       |
| `ca:server`                       | generate local server TLS CA                                    |
| `ca:client`                       | generate local client-signing CA                                |
| `ca:all`                          | generate both local CAs                                         |
| `certs:server`                    | create Keycloak server TLS certificate                          |
| `certs:client-truststore`         | create Keycloak inbound client certificate truststore           |
| `certs`                           | create required local certs and Keycloak client truststore      |
| `certs:regen`                     | regenerate local certs while keeping the existing server CA     |
| `certs:regen:all`                 | regenerate local certs including the server CA                  |
| `certs:config-cli-truststore`     | create truststore used by keycloak-config-cli                   |
| `start`                           | start Keycloak and Postgres with Docker Compose                 |
| `stop`                            | stop Keycloak and Postgres                                      |
| `logs`                            | follow Keycloak logs                                            |
| `config:apply`                    | run keycloak-config-cli and apply config-as-code realm settings |
| `config:apply:debug`              | run keycloak-config-cli with debug logging                      |
| `config:logs`                     | follow keycloak-config-cli logs                                 |

Task implementations live in `scripts/*.sh` so certificate and Compose logic stays testable and maintainable. Certificate tasks are centralized in `scripts/certs.sh`.

Certificate generation can be customized with env vars such as `CERTS_DIR`, `SERVER_CERT_SAN`, `TRUSTSTORE_PASSWORD`, `SERVER_CA_DAYS`, `CLIENT_CA_DAYS`, `SERVER_CERT_DAYS`, and `KEY_SIZE`.

Shell aliases use mise `[shell_alias]` and are auto-managed when your shell runs `mise activate`. For example, `start`, `logs`, and `config` map to `mise run start`, `mise run logs`, and `mise run config:apply`.

Compose commands use `scripts/compose.sh`, which provides shortcuts like `start`, `stop`, `logs`, and `config-apply`, plus passthrough Compose args. It selects the first available runtime:

1. `COMPOSE_CMD` override, for example `COMPOSE_CMD="docker compose" mise run start`
2. `podman-compose`
3. Docker Compose v2: `docker compose`
4. legacy `docker-compose`

## Generate local dev certs

This project uses two certificate chains.

| chain           | purpose                                                  |
| --------------- | -------------------------------------------------------- |
| server chain    | Keycloak proves its identity to browsers and API clients |
| client CA chain | callers prove their machine identity to Keycloak         |

### Create directory structure

```bash
mkdir -p certs/server certs/client-ca certs/internal-ca
```

### Generate the server certificate

Create a local CA for browser trust:

```bash
openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
  -keyout certs/server/server-ca.key \
  -out certs/server/server-ca.crt \
  -subj "/CN=keycloak-playground-server-ca" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"
```

Create the server key and CSR:

```bash
openssl req -newkey rsa:4096 -nodes \
  -keyout certs/server/tls.key \
  -out certs/server/tls.csr \
  -subj "/CN=localhost"
```

Sign the server certificate:

```bash
cat > certs/server/tls.ext <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,DNS:keycloak,IP:127.0.0.1
EOF

openssl x509 -req -days 365 \
  -in certs/server/tls.csr \
  -CA certs/server/server-ca.crt \
  -CAkey certs/server/server-ca.key \
  -CAcreateserial \
  -out certs/server/tls.crt \
  -extfile certs/server/tls.ext
```

> **Note:** The server cert must be a leaf cert (`CA:FALSE`). Browsers such as Firefox reject CA certificates used directly as website certificates (`MOZILLA_PKIX_ERROR_CA_CERT_USED_AS_END_ENTITY`).

Required SANs:

| SAN             | used by                                                    |
| --------------- | ---------------------------------------------------------- |
| `DNS:localhost` | browser or curl from the host via `https://localhost:8443` |
| `DNS:keycloak`  | Compose internal service DNS used by config-cli            |
| `IP:127.0.0.1`  | local loopback clients                                     |

### Generate the client-signing CA

```bash
openssl req -x509 -newkey rsa:4096 -nodes -days 365 \
  -keyout certs/client-ca/client-ca.key \
  -out certs/client-ca/client-ca.crt \
  -subj "/CN=keycloak-playground-client-ca"
```

This CA signs client certificates such as `billing-worker`. It is separate from the server CA so its trust scope is limited.

### Create the Keycloak inbound client truststore

```bash
keytool -importcert -noprompt \
  -alias client-ca \
  -file certs/client-ca/client-ca.crt \
  -keystore certs/client-ca/client-truststore.p12 \
  -storetype PKCS12 \
  -storepass changeit
```

Keycloak now trusts client certificates signed by `certs/client-ca/client-ca.crt` at the TLS layer. TLS trust is the first check; Keycloak client authentication then verifies that the certificate subject matches the configured OIDC client.

> **macOS only:** Import the server CA into the system keychain so browsers trust your local Keycloak instance.
>
> ```bash
> sudo security add-trusted-cert \
>   -d -r trustRoot \
>   -k /Library/Keychains/System.keychain \
>   certs/server/server-ca.crt
> ```

---

## Config as code

Realm configuration is managed from YAML files instead of the Admin Console.

See [`config-as-code/README.md`](config-as-code/README.md) for the overview and tooling options.

---

## Add a certificate-authenticated client

Use this pattern for machine clients that authenticate with `client_credentials` and an X.509 certificate. The example uses `billing-worker` as the client ID.

### 1. Choose a certificate subject

```text
CN=billing-worker
```

Keep the CN aligned with the X.509 subject DN matcher configured on the Keycloak OIDC client.

### 2. Generate a private key and CSR

```bash
mkdir -p certs/clients/billing-worker

openssl req -newkey rsa:4096 -nodes \
  -keyout certs/clients/billing-worker/billing-worker.key \
  -out certs/clients/billing-worker/billing-worker.csr \
  -subj "/CN=billing-worker"
```

### 3. Sign the CSR with the client CA

```bash
openssl x509 -req -days 365 \
  -in certs/clients/billing-worker/billing-worker.csr \
  -CA certs/client-ca/client-ca.crt \
  -CAkey certs/client-ca/client-ca.key \
  -CAcreateserial \
  -out certs/clients/billing-worker/billing-worker.crt
```

### 4. Create a PKCS12 keystore for the caller

```bash
openssl pkcs12 -export \
  -inkey certs/clients/billing-worker/billing-worker.key \
  -in certs/clients/billing-worker/billing-worker.crt \
  -certfile certs/client-ca/client-ca.crt \
  -out certs/clients/billing-worker/billing-worker.p12 \
  -name billing-worker \
  -passout pass:changeit
```

### 5. Create a truststore for the caller (if needed)

Skip this if the caller already trusts `certs/server/server-ca.crt`.

```bash
keytool -importcert -noprompt \
  -alias keycloak-server-ca \
  -file certs/server/server-ca.crt \
  -keystore certs/clients/billing-worker/keycloak-truststore.p12 \
  -storetype PKCS12 \
  -storepass changeit
```

### 6. Create the Keycloak OIDC client

In the target realm, create an OIDC client with these settings:

| setting                | value                                |
| ---------------------- | ------------------------------------ |
| Realm                  | target realm, for example `acme-org` |
| Client ID              | `billing-worker`                     |
| Client type            | OpenID Connect                       |
| Client authentication  | `On`                                 |
| Standard flow          | `Off` unless needed                  |
| Direct access grants   | `Off` unless needed                  |
| Service accounts roles | `On`                                 |
| Client Authenticator   | X509 certificate                     |
| Certificate subject DN | `CN=billing-worker`                  |

### 7. Assign service account roles

Grant only required roles to `service-account-billing-worker`.

### 8. Configure the caller

**Java JVM flags:**

```bash
-Djavax.net.ssl.keyStore=/path/to/billing-worker.p12 \
-Djavax.net.ssl.keyStorePassword=changeit \
-Djavax.net.ssl.keyStoreType=PKCS12 \
-Djavax.net.ssl.trustStore=/path/to/keycloak-truststore.p12 \
-Djavax.net.ssl.trustStorePassword=changeit \
-Djavax.net.ssl.trustStoreType=PKCS12
```

**curl smoke test:**

```bash
curl --cert certs/clients/billing-worker/billing-worker.crt \
  --key certs/clients/billing-worker/billing-worker.key \
  --cacert certs/server/server-ca.crt \
  -d grant_type=client_credentials \
  -d client_id=billing-worker \
  https://localhost:8443/realms/acme-org/protocol/openid-connect/token
```

**Authentication flow:**

```text
caller presents billing-worker.crt
  → Keycloak verifies it chains to client-ca.crt (TLS layer)
  → Keycloak matches certificate subject DN to client billing-worker
  → token endpoint issues a client_credentials token
```

---

## Reference

### Certificate file map

| file                                    | purpose                                             | used by                                 | mounted at                                      |
| --------------------------------------- | --------------------------------------------------- | --------------------------------------- | ----------------------------------------------- |
| `certs/server/server-ca.crt`            | local CA for the Keycloak HTTPS server cert         | import into browser or OS trust         | not mounted                                     |
| `certs/server/server-ca.key`            | private key for signing the HTTPS cert              | local dev only                          | not mounted                                     |
| `certs/server/tls.crt`                  | Keycloak HTTPS leaf cert, signed by `server-ca.crt` | Keycloak presents this to clients       | `/opt/keycloak/conf/tls/tls.crt`                |
| `certs/server/tls.key`                  | private key for the server cert                     | Keycloak                                | `/opt/keycloak/conf/tls/tls.key`                |
| `certs/client-ca/client-ca.crt`         | CA for trusted client certs                         | imported into Keycloak truststore       | source for `client-truststore.p12`              |
| `certs/client-ca/client-ca.key`         | private key for signing client certs                | local dev only                          | not mounted                                     |
| `certs/client-ca/client-truststore.p12` | truststore containing `client-ca.crt`               | Keycloak verifies incoming client certs | `/opt/keycloak/conf/mtls/client-truststore.p12` |
| `certs/internal-ca/*`                   | optional CAs for Keycloak outbound HTTPS            | Keycloak JVM trust                      | `/opt/keycloak/conf/truststores/internal-ca`    |

### Environment variables

Defaults are set in `.env.example`. Copy to `.env` to override.

| variable                        | default     | description                                              |
| ------------------------------- | ----------- | -------------------------------------------------------- |
| `KEYCLOAK_START_COMMAND`        | `start-dev` | `start-dev` for dev mode, `start` for production mode    |
| `KC_BOOTSTRAP_ADMIN_USERNAME`   | `admin`     | initial admin username                                   |
| `KC_BOOTSTRAP_ADMIN_PASSWORD`   | `admin`     | initial admin password                                   |
| `KC_HOSTNAME`                   | `localhost` | canonical hostname; required in production mode          |
| `KC_HOSTNAME_STRICT`            | `false`     | set `true` to reject requests on other hostnames         |
| `KC_HTTPS_CLIENT_AUTH`          | `request`   | `request` = optional client cert, `required` = hard mTLS |
| `KC_HTTPS_TRUST_STORE_PASSWORD` | `changeit`  | password for the client truststore                       |
| `KC_LOG_CONSOLE_COLOR`          | `true`      | enable Keycloak ANSI-colored console logs                |
| `POSTGRES_DB`                   | `keycloak`  | database name                                            |
| `POSTGRES_USER`                 | `keycloak`  | database user                                            |
| `POSTGRES_PASSWORD`             | `keycloak`  | database password                                        |

### Trust model

| use case                      | Keycloak configuration                                       |
| ----------------------------- | ------------------------------------------------------------ |
| Serve HTTPS                   | `KC_HTTPS_CERTIFICATE_FILE`, `KC_HTTPS_CERTIFICATE_KEY_FILE` |
| Verify inbound client certs   | `KC_HTTPS_CLIENT_AUTH`, `KC_HTTPS_TRUST_STORE_FILE`          |
| Trust outbound internal HTTPS | `KC_TRUSTSTORE_PATHS`                                        |

Files under `certs/internal-ca/` are for Keycloak outbound HTTPS trust only. They are not server certificates and do not affect client certificate verification.

### mTLS client auth modes

Set via `KC_HTTPS_CLIENT_AUTH` in `.env` or as an environment override.

| mode       | behaviour                                                            |
| ---------- | -------------------------------------------------------------------- |
| `request`  | Keycloak asks for a client cert but still allows callers without one |
| `required` | every HTTPS caller must present a trusted client cert                |

Enable hard mTLS for a single run:

```bash
KC_HTTPS_CLIENT_AUTH=required docker compose up
```

### Runtime modes

| mode          | command     | notes                                          |
| ------------- | ----------- | ---------------------------------------------- |
| dev (default) | `start-dev` | relaxed caches, hot reload, no hostname strict |
| production    | `start`     | requires `KC_HOSTNAME`, caches enabled         |

Production with a fixed hostname:

```bash
KEYCLOAK_START_COMMAND=start KC_HOSTNAME=auth.example.com KC_HOSTNAME_STRICT=true docker compose up
```

Dynamic multi-domain issuers (no fixed hostname):

```bash
KEYCLOAK_START_COMMAND=start KC_HOSTNAME_STRICT=false docker compose up
```

Do not set `KC_HOSTNAME` in this case; keep `KC_PROXY_HEADERS=xforwarded`.

---

## OpenShift notes

### Passthrough route

Use a passthrough route when Keycloak must see the original TLS connection and client certificate.

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: keycloak
spec:
  host: auth.example.com
  to:
    kind: Service
    name: keycloak
  port:
    targetPort: https
  tls:
    termination: passthrough
```

Keycloak serves the public certificate directly. Mount:

```text
/opt/keycloak/conf/tls/tls.crt
/opt/keycloak/conf/tls/tls.key
```

If you serve multiple hostnames, include all of them as SANs in `tls.crt`.

### Service definition

```yaml
apiVersion: v1
kind: Service
metadata:
  name: keycloak
spec:
  selector:
    app: keycloak
  ports:
    - name: https
      port: 8443
      targetPort: 8443
```
