# Keycloak playground

Local Keycloak `26.6.1` playground with:

- Postgres backing DB
- HTTPS on `8443`
- mTLS-ready inbound client certificate validation
- optional config-as-code imports

This repo is for learning and local experiments. Defaults are intentionally dev-friendly.

## Mental model

```text
browser/API client -> HTTPS -> Keycloak -> Postgres
machine client -> HTTPS + client cert -> Keycloak token endpoint
config-as-code tool -> HTTPS + client cert -> Keycloak Admin API
```

Key concepts:

| concept              | meaning                                                             |
| -------------------- | ------------------------------------------------------------------- |
| HTTPS server cert    | cert Keycloak presents to clients so they can trust Keycloak        |
| client cert          | cert a caller presents to Keycloak to prove machine identity        |
| client CA            | CA Keycloak trusts for validating client certs                      |
| truststore           | file containing trusted certificates/CAs                            |
| keystore             | file containing a private key + certificate                         |
| `client_credentials` | OAuth grant for machine-to-machine tokens, no user/browser involved |

## Stack

| component | image / port                       |
| --------- | ---------------------------------- |
| Keycloak  | `quay.io/keycloak/keycloak:26.6.1` |
| Postgres  | `postgres:17-alpine`               |
| HTTPS     | `https://localhost:8443`           |
| health    | `localhost:9000`                   |

No custom Keycloak image is used.

## Quick start

1. Copy env file.

```bash
cp .env.example .env
```

2. Generate certificates. See [Generate local dev certs](#generate-local-dev-certs).

3. Start stack.

```bash
podman-compose up -d
podman-compose logs -f keycloak
# or

docker-compose up -d
docker-compose logs -f keycloak
```

4. Open admin UI.

```text
https://localhost:8443
```

Default admin:

```text
admin / admin
```

Reset local DB:

```bash
podman-compose down -v
# or

docker-compose down -v
```

## Required files

Keycloak will not start correctly without these files:

```text
certs/server/tls.crt
certs/server/tls.key
certs/client-ca/client-truststore.p12
```

Optional outbound trust CAs:

```text
certs/internal-ca/*.crt
certs/internal-ca/*.pem
```

## Generate local dev certs

This project uses two certificate chains.

| chain                    | purpose                                              |
| ------------------------ | ---------------------------------------------------- |
| server cert              | Keycloak proves its identity to browsers/API clients |
| client CA + client certs | callers prove their identity to Keycloak             |

### File map

| file                                    | purpose                                                      | used by                                 | mounted at                                      |
| --------------------------------------- | ------------------------------------------------------------ | --------------------------------------- | ----------------------------------------------- |
| `certs/server/server-ca.crt`            | local CA certificate for Keycloak HTTPS server cert          | import into browser/OS trust            | not mounted                                     |
| `certs/server/server-ca.key`            | local CA private key for signing Keycloak HTTPS cert         | local dev only                          | not mounted                                     |
| `certs/server/tls.crt`                  | Keycloak HTTPS server certificate, signed by `server-ca.crt` | Keycloak presents this to clients       | `/opt/keycloak/conf/tls/tls.crt`                |
| `certs/server/tls.key`                  | private key for server certificate                           | Keycloak                                | `/opt/keycloak/conf/tls/tls.key`                |
| `certs/client-ca/client-ca.crt`         | separate CA certificate for trusted client certs             | imported into Keycloak truststore       | source for `client-truststore.p12`              |
| `certs/client-ca/client-ca.key`         | private key for signing local client certs                   | local dev only                          | not mounted                                     |
| `certs/client-ca/client-truststore.p12` | truststore containing `client-ca.crt`                        | Keycloak verifies incoming client certs | `/opt/keycloak/conf/mtls/client-truststore.p12` |
| `certs/internal-ca/*`                   | optional CAs for outbound HTTPS from Keycloak                | Keycloak JVM trust                      | `/opt/keycloak/conf/truststores/internal-ca`    |

### 1. Generate Keycloak HTTPS server certificate

Create a local CA for browser trust:

```bash
mkdir -p certs/server certs/client-ca certs/internal-ca

openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
  -keyout certs/server/server-ca.key \
  -out certs/server/server-ca.crt \
  -subj "/CN=keycloak-playground-server-ca" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"
```

Create Keycloak server key and CSR:

```bash
openssl req -newkey rsa:4096 -nodes \
  -keyout certs/server/tls.key \
  -out certs/server/tls.csr \
  -subj "/CN=localhost"
```

Sign the server cert with `CA:FALSE` and server auth usage:

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

Why: clients need a server certificate when connecting to Keycloak. Firefox rejects CA certificates used directly as website certificates (`MOZILLA_PKIX_ERROR_CA_CERT_USED_AS_END_ENTITY`), so `tls.crt` must be a leaf cert with `CA:FALSE`.

Required SANs:

| SAN             | used by                                             |
| --------------- | --------------------------------------------------- |
| `DNS:localhost` | browser/curl from host via `https://localhost:8443` |
| `DNS:keycloak`  | Compose containers via `https://keycloak:8443`      |
| `IP:127.0.0.1`  | local loopback clients                              |

### 2. Generate local client-signing CA

```bash
openssl req -x509 -newkey rsa:4096 -nodes -days 365 \
  -keyout certs/client-ca/client-ca.key \
  -out certs/client-ca/client-ca.crt \
  -subj "/CN=keycloak-playground-client-ca"
```

Why: this CA signs client certificates such as `keycloak-config-cli` or `billing-worker`.

### 3. Create Keycloak inbound client truststore

```bash
keytool -importcert -noprompt \
  -alias client-ca \
  -file certs/client-ca/client-ca.crt \
  -keystore certs/client-ca/client-truststore.p12 \
  -storetype PKCS12 \
  -storepass changeit
```

Result: Keycloak trusts client certificates signed by `certs/client-ca/client-ca.crt` at the TLS layer.

Important: TLS trust is only the first check. Keycloak client authentication still verifies that the certificate subject matches the configured OIDC client.

### Optional: trust local server cert on macOS

```bash
sudo security add-trusted-cert \
  -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  certs/server/server-ca.crt
```

## Config as code

Config-as-code docs live under:

```text
config-as-code/
```

Current options:

| path                                  | purpose                                    |
| ------------------------------------- | ------------------------------------------ |
| `config-as-code/keycloak-config-cli/` | adorsys `keycloak-config-cli` YAML imports |
| `config-as-code/terraform/`           | planned Terraform approach                 |

Current YAML realm import:

```text
config-as-code/keycloak-config-cli/realms/acme-org.yaml
```

## Add another certificate-authenticated client

Use this pattern for machine clients that need `client_credentials` with certificate-based authentication.

Example client ID:

```text
billing-worker
```

### 1. Pick certificate identity

```text
CN=billing-worker
```

Keep this aligned with the Keycloak client's X509 subject DN matcher.

### 2. Generate private key and CSR

```bash
mkdir -p certs/clients/billing-worker

openssl req -newkey rsa:4096 -nodes \
  -keyout certs/clients/billing-worker/billing-worker.key \
  -out certs/clients/billing-worker/billing-worker.csr \
  -subj "/CN=billing-worker"
```

### 3. Sign CSR with client CA

```bash
openssl x509 -req -days 365 \
  -in certs/clients/billing-worker/billing-worker.csr \
  -CA certs/client-ca/client-ca.crt \
  -CAkey certs/client-ca/client-ca.key \
  -CAcreateserial \
  -out certs/clients/billing-worker/billing-worker.crt
```

### 4. Create Java PKCS12 keystore

```bash
openssl pkcs12 -export \
  -inkey certs/clients/billing-worker/billing-worker.key \
  -in certs/clients/billing-worker/billing-worker.crt \
  -certfile certs/client-ca/client-ca.crt \
  -out certs/clients/billing-worker/billing-worker.p12 \
  -name billing-worker \
  -passout pass:changeit
```

### 5. Create server truststore if needed

If the caller already trusts `certs/server/tls.crt`, skip this.

```bash
keytool -importcert -noprompt \
  -alias keycloak-server \
  -file certs/server/tls.crt \
  -keystore certs/clients/billing-worker/keycloak-truststore.p12 \
  -storetype PKCS12 \
  -storepass changeit
```

### 6. Create Keycloak OIDC client

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

Grant only required roles to:

```text
service-account-billing-worker
```

### 8. Configure caller

Java example:

```bash
-Djavax.net.ssl.keyStore=/path/to/billing-worker.p12 \
-Djavax.net.ssl.keyStorePassword=changeit \
-Djavax.net.ssl.keyStoreType=PKCS12 \
-Djavax.net.ssl.trustStore=/path/to/keycloak-truststore.p12 \
-Djavax.net.ssl.trustStorePassword=changeit \
-Djavax.net.ssl.trustStoreType=PKCS12
```

curl smoke test:

```bash
curl --cert certs/clients/billing-worker/billing-worker.crt \
  --key certs/clients/billing-worker/billing-worker.key \
  --cacert certs/server/tls.crt \
  -d grant_type=client_credentials \
  -d client_id=billing-worker \
  https://localhost:8443/realms/acme-org/protocol/openid-connect/token
```

Flow summary:

```text
caller presents billing-worker.crt
-> Keycloak verifies it chains to client-ca.crt
-> Keycloak matches subject DN to client billing-worker
-> token endpoint issues client_credentials token
```

## Runtime modes

Default local mode:

```text
KEYCLOAK_START_COMMAND=start-dev
```

Production-like mode:

```bash
KEYCLOAK_START_COMMAND=start podman-compose up
# or
KEYCLOAK_START_COMMAND=start docker-compose up
```

For one canonical hostname:

```bash
KEYCLOAK_START_COMMAND=start \
KC_HOSTNAME=auth.example.com \
KC_HOSTNAME_STRICT=true \
podman-compose up
```

For dynamic multi-domain issuers, do not set `KC_HOSTNAME`; keep:

```text
KC_HOSTNAME_STRICT=false
KC_PROXY_HEADERS=xforwarded
```

## Trust model

| use case                      | config                                                       |
| ----------------------------- | ------------------------------------------------------------ |
| Serve HTTPS                   | `KC_HTTPS_CERTIFICATE_FILE`, `KC_HTTPS_CERTIFICATE_KEY_FILE` |
| Verify inbound client certs   | `KC_HTTPS_CLIENT_AUTH`, `KC_HTTPS_TRUST_STORE_FILE`          |
| Trust outbound internal HTTPS | `KC_TRUSTSTORE_PATHS`                                        |

Mounted internal CAs in `certs/internal-ca/` are for Keycloak outbound HTTPS trust only. They are not server certs and do not verify incoming client certs.

## mTLS client authentication mode

Current Compose config:

```text
KC_HTTPS_CLIENT_AUTH=request
KC_HTTPS_TRUST_STORE_FILE=/opt/keycloak/conf/mtls/client-truststore.p12
```

Mode behavior:

| mode       | behavior                                                             |
| ---------- | -------------------------------------------------------------------- |
| `request`  | Keycloak asks for a client cert but still allows callers without one |
| `required` | every HTTPS caller must present a trusted client cert                |

Use hard mTLS:

```bash
KC_HTTPS_CLIENT_AUTH=required podman-compose up
# or
KC_HTTPS_CLIENT_AUTH=required docker-compose up
```

## OpenShift notes

### Passthrough Route

Use passthrough when Keycloak must see the original TLS connection and client certificate.

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: keycloak-dhohner-de
spec:
  host: dhohner.de
  to:
    kind: Service
    name: keycloak
  port:
    targetPort: https
  tls:
    termination: passthrough
```

Keycloak serves the public certificate directly. Must provide/mount:

```text
/opt/keycloak/conf/tls/tls.crt
/opt/keycloak/conf/tls/tls.key
```

For hosts `dhohner.de`, `dhohner.at`, `dhohner.intern`, the served cert needs SANs for all three names.

### Service port

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
