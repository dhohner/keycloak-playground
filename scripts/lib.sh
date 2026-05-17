#!/usr/bin/env bash
# Shared helpers for repository scripts. Source only.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "scripts/lib.sh must be sourced, not executed" >&2
  exit 2
fi

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

CERTS_DIR="${CERTS_DIR:-${PROJECT_ROOT}/certs}"
SERVER_CERT_DIR="${SERVER_CERT_DIR:-${CERTS_DIR}/server}"
CLIENT_CA_DIR="${CLIENT_CA_DIR:-${CERTS_DIR}/client-ca}"
INTERNAL_CA_DIR="${INTERNAL_CA_DIR:-${CERTS_DIR}/internal-ca}"
CONFIG_CLI_CERT_DIR="${CONFIG_CLI_CERT_DIR:-${CERTS_DIR}/config-cli}"

SERVER_CA_CN="${SERVER_CA_CN:-keycloak-playground-server-ca}"
CLIENT_CA_CN="${CLIENT_CA_CN:-keycloak-playground-client-ca}"
SERVER_CERT_CN="${SERVER_CERT_CN:-localhost}"
SERVER_CERT_SAN="${SERVER_CERT_SAN:-DNS:localhost,DNS:keycloak,IP:127.0.0.1}"
SERVER_CA_DAYS="${SERVER_CA_DAYS:-3650}"
CLIENT_CA_DAYS="${CLIENT_CA_DAYS:-365}"
SERVER_CERT_DAYS="${SERVER_CERT_DAYS:-365}"
TRUSTSTORE_PASSWORD="${TRUSTSTORE_PASSWORD:-changeit}"
KEY_SIZE="${KEY_SIZE:-4096}"

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fatal() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fatal "missing required command: $1"
}

ensure_dir() {
  mkdir -p "$@"
}

exists_all() {
  local path
  for path in "$@"; do
    [[ -e "$path" ]] || return 1
  done
}

remove_files() {
  rm -f -- "$@"
}
