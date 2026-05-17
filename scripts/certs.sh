#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'USAGE'
Usage: scripts/certs.sh <command> [options]

Commands:
  server-ca                     Generate server CA if missing
  client-ca                     Generate client CA if missing
  local-ca                      Generate both CAs if missing
  server-cert                   Generate server TLS cert if missing
  client-truststore             Generate Keycloak client truststore if missing
  config-cli-truststore         Generate config-cli truststore if missing
  terraform                     Generate Terraform provider mTLS certificate if missing
  terraform-client-cert         Alias for terraform
  all                           Generate required certs/truststores if missing
  regen [--regenerate-server-ca] Regenerate local certs; keeps server CA by default

Config via env:
  CERTS_DIR, SERVER_CERT_SAN, TRUSTSTORE_PASSWORD, SERVER_CA_DAYS,
  CLIENT_CA_DAYS, SERVER_CERT_DAYS, KEY_SIZE,
  TERRAFORM_CLIENT_CERT_CN, TERRAFORM_CLIENT_CERT_DAYS
USAGE
}

generate_server_ca() {
  require_cmd openssl
  ensure_dir "$SERVER_CERT_DIR"

  if exists_all "$SERVER_CERT_DIR/server-ca.crt" "$SERVER_CERT_DIR/server-ca.key"; then
    log "server CA exists; skipping"
    return 0
  fi

  openssl req -x509 -newkey "rsa:${KEY_SIZE}" -nodes -days "$SERVER_CA_DAYS" \
    -keyout "$SERVER_CERT_DIR/server-ca.key" \
    -out "$SERVER_CERT_DIR/server-ca.crt" \
    -subj "/CN=${SERVER_CA_CN}" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
}

generate_client_ca() {
  require_cmd openssl
  ensure_dir "$CLIENT_CA_DIR" "$INTERNAL_CA_DIR"

  if exists_all "$CLIENT_CA_DIR/client-ca.crt" "$CLIENT_CA_DIR/client-ca.key"; then
    log "client CA exists; skipping"
    return 0
  fi

  openssl req -x509 -newkey "rsa:${KEY_SIZE}" -nodes -days "$CLIENT_CA_DAYS" \
    -keyout "$CLIENT_CA_DIR/client-ca.key" \
    -out "$CLIENT_CA_DIR/client-ca.crt" \
    -subj "/CN=${CLIENT_CA_CN}"
}

generate_server_cert() {
  require_cmd openssl
  ensure_dir "$SERVER_CERT_DIR"

  if exists_all "$SERVER_CERT_DIR/tls.crt" "$SERVER_CERT_DIR/tls.key"; then
    log "server certificate exists; skipping"
    return 0
  fi

  exists_all "$SERVER_CERT_DIR/server-ca.crt" "$SERVER_CERT_DIR/server-ca.key" || \
    fatal "missing server CA; run: mise run ca:server"

  openssl req -newkey "rsa:${KEY_SIZE}" -nodes \
    -keyout "$SERVER_CERT_DIR/tls.key" \
    -out "$SERVER_CERT_DIR/tls.csr" \
    -subj "/CN=${SERVER_CERT_CN}"

  cat > "$SERVER_CERT_DIR/tls.ext" <<EXT
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=${SERVER_CERT_SAN}
EXT

  openssl x509 -req -days "$SERVER_CERT_DAYS" \
    -in "$SERVER_CERT_DIR/tls.csr" \
    -CA "$SERVER_CERT_DIR/server-ca.crt" \
    -CAkey "$SERVER_CERT_DIR/server-ca.key" \
    -CAcreateserial \
    -out "$SERVER_CERT_DIR/tls.crt" \
    -extfile "$SERVER_CERT_DIR/tls.ext"
}

generate_client_truststore() {
  require_cmd keytool
  ensure_dir "$CLIENT_CA_DIR"

  if [[ -f "$CLIENT_CA_DIR/client-truststore.p12" ]]; then
    log "client truststore exists; skipping"
    return 0
  fi

  [[ -f "$CLIENT_CA_DIR/client-ca.crt" ]] || fatal "missing client CA; run: mise run ca:client"

  keytool -importcert -noprompt \
    -alias client-ca \
    -file "$CLIENT_CA_DIR/client-ca.crt" \
    -keystore "$CLIENT_CA_DIR/client-truststore.p12" \
    -storetype PKCS12 \
    -storepass "$TRUSTSTORE_PASSWORD"
}

generate_config_cli_truststore() {
  require_cmd keytool
  ensure_dir "$CONFIG_CLI_CERT_DIR"

  if [[ -f "$CONFIG_CLI_CERT_DIR/keycloak-truststore.p12" ]]; then
    log "config-cli truststore exists; skipping"
    return 0
  fi

  [[ -f "$SERVER_CERT_DIR/server-ca.crt" ]] || fatal "missing server CA; run: mise run ca:server"

  keytool -importcert -noprompt \
    -alias keycloak-server-ca \
    -file "$SERVER_CERT_DIR/server-ca.crt" \
    -keystore "$CONFIG_CLI_CERT_DIR/keycloak-truststore.p12" \
    -storetype PKCS12 \
    -storepass "$TRUSTSTORE_PASSWORD"
}

generate_terraform_client_cert() {
  require_cmd openssl
  ensure_dir "$TERRAFORM_CLIENT_CERT_DIR"

  if exists_all "$TERRAFORM_CLIENT_CERT_DIR/terraform-provider.crt" "$TERRAFORM_CLIENT_CERT_DIR/terraform-provider.key"; then
    log "Terraform provider mTLS client certificate exists; skipping"
  else
    exists_all "$CLIENT_CA_DIR/client-ca.crt" "$CLIENT_CA_DIR/client-ca.key" || \
      fatal "missing client CA; run: mise run ca:client"

    openssl req -newkey "rsa:${KEY_SIZE}" -nodes \
      -keyout "$TERRAFORM_CLIENT_CERT_DIR/terraform-provider.key" \
      -out "$TERRAFORM_CLIENT_CERT_DIR/terraform-provider.csr" \
      -subj "/CN=${TERRAFORM_CLIENT_CERT_CN}"

    cat > "$TERRAFORM_CLIENT_CERT_DIR/terraform-provider.ext" <<EXT
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=clientAuth
EXT

    openssl x509 -req -days "$TERRAFORM_CLIENT_CERT_DAYS" \
      -in "$TERRAFORM_CLIENT_CERT_DIR/terraform-provider.csr" \
      -CA "$CLIENT_CA_DIR/client-ca.crt" \
      -CAkey "$CLIENT_CA_DIR/client-ca.key" \
      -CAcreateserial \
      -out "$TERRAFORM_CLIENT_CERT_DIR/terraform-provider.crt" \
      -extfile "$TERRAFORM_CLIENT_CERT_DIR/terraform-provider.ext"
  fi
}

regenerate() {
  local regenerate_server_ca=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --regenerate-server-ca) regenerate_server_ca=true ;;
      -h|--help) usage; exit 0 ;;
      *) fatal "unknown option for regen: $1" ;;
    esac
    shift
  done

  remove_files \
    "$SERVER_CERT_DIR/tls.crt" \
    "$SERVER_CERT_DIR/tls.key" \
    "$SERVER_CERT_DIR/tls.csr" \
    "$SERVER_CERT_DIR/tls.ext" \
    "$CLIENT_CA_DIR/client-ca.crt" \
    "$CLIENT_CA_DIR/client-ca.key" \
    "$CLIENT_CA_DIR/client-ca.srl" \
    "$CLIENT_CA_DIR/client-truststore.p12" \
    "$CONFIG_CLI_CERT_DIR/keycloak-truststore.p12" \
    "$TERRAFORM_CLIENT_CERT_DIR/terraform-provider.crt" \
    "$TERRAFORM_CLIENT_CERT_DIR/terraform-provider.key" \
    "$TERRAFORM_CLIENT_CERT_DIR/terraform-provider.csr" \
    "$TERRAFORM_CLIENT_CERT_DIR/terraform-provider.ext" \
    "$TERRAFORM_CLIENT_CERT_DIR/jwt-signing.key" \
    "$TERRAFORM_CLIENT_CERT_DIR/jwt-signing.crt" \
    "$TERRAFORM_CLIENT_CERT_DIR/jwt-signing.pub"

  if [[ "$regenerate_server_ca" == true ]]; then
    remove_files \
      "$SERVER_CERT_DIR/server-ca.crt" \
      "$SERVER_CERT_DIR/server-ca.key" \
      "$SERVER_CERT_DIR/server-ca.srl"
  fi

  generate_server_ca
  generate_client_ca
  generate_server_cert
  generate_client_truststore
  generate_terraform_client_cert
}

main() {
  local command="${1:-}"
  [[ -n "$command" ]] || { usage; exit 2; }
  shift || true

  case "$command" in
    server-ca) generate_server_ca "$@" ;;
    client-ca) generate_client_ca "$@" ;;
    local-ca) generate_server_ca; generate_client_ca ;;
    server-cert) generate_server_ca; generate_server_cert ;;
    client-truststore) generate_client_ca; generate_client_truststore ;;
    config-cli-truststore) generate_config_cli_truststore ;;
    terraform|terraform-client-cert) generate_client_ca; generate_terraform_client_cert ;;
    all) generate_server_ca; generate_client_ca; generate_server_cert; generate_client_truststore ;;
    regen) regenerate "$@" ;;
    -h|--help|help) usage ;;
    *) fatal "unknown command: $command" ;;
  esac
}

main "$@"
