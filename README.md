# Keycloak playground

Local Keycloak `26.6.1` with HTTPS, mTLS-ready config, Postgres, and mounted CA trust.

## Stack

- Keycloak: `quay.io/keycloak/keycloak:26.6.1`
- Database: `postgres:17-alpine`
- HTTPS: `8443`
- Health: `9000`
- No custom Keycloak image / no `Containerfile`

## Start

Create certs first, then start with Docker or Podman.

```bash
cp .env.example .env
podman compose up
# or
docker compose up
```

Open:

```text
https://localhost:8443
```

Default admin:

```text
admin / admin
```

Reset local DB:

```bash
podman compose down -v
# or
docker compose down -v
```

## Required files

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

```bash
mkdir -p certs/server certs/client-ca certs/internal-ca

openssl req -x509 -newkey rsa:4096 -nodes -days 365 \
  -keyout certs/server/tls.key \
  -out certs/server/tls.crt \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

openssl req -x509 -newkey rsa:4096 -nodes -days 365 \
  -keyout certs/client-ca/client-ca.key \
  -out certs/client-ca/client-ca.crt \
  -subj "/CN=keycloak-playground-client-ca"

keytool -importcert -noprompt \
  -alias client-ca \
  -file certs/client-ca/client-ca.crt \
  -keystore certs/client-ca/client-truststore.p12 \
  -storetype PKCS12 \
  -storepass changeit
```

## Runtime modes

Default:

```text
KEYCLOAK_START_COMMAND=start-dev
```

Production mode:

```bash
KEYCLOAK_START_COMMAND=start podman compose up
# or
KEYCLOAK_START_COMMAND=start docker compose up
```

For one canonical hostname:

```bash
KEYCLOAK_START_COMMAND=start \
KC_HOSTNAME=auth.example.com \
KC_HOSTNAME_STRICT=true \
podman compose up
```

For dynamic multi-domain issuers, do **not** set `KC_HOSTNAME`; keep:

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

Mounted internal CAs in `certs/internal-ca/` are for **Keycloak outbound HTTPS trust**. They are not server certs and do not verify incoming client certs.

## mTLS client authentication

Current compose enables HTTPS client auth mode via:

```text
KC_HTTPS_CLIENT_AUTH=request
KC_HTTPS_TRUST_STORE_FILE=/opt/keycloak/conf/mtls/client-truststore.p12
```

Use hard mTLS:

```bash
KC_HTTPS_CLIENT_AUTH=required podman compose up
# or
KC_HTTPS_CLIENT_AUTH=required docker compose up
```

`request` allows browser/admin access without a client cert. `required` requires every HTTPS caller to present a trusted client cert.

## OpenShift notes

### Passthrough Route

Use when Keycloak must see the original TLS connection/client certificate.

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
