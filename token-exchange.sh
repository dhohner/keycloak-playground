#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Keycloak BFF Token Exchange Flow Test
#
# Flow:
#   1. Get user token as mobile-app via Resource Owner Password Credentials grant
#   2. Exchange that token as mobile-bff for an orders-api audience token
#   3. Decode both JWTs
#   4. Optionally call downstream API with exchanged token
# ------------------------------------------------------------------------------

# ===== Required config =========================================================

KC_BASE_URL="${KC_BASE_URL:-https://localhost:8443}"
KC_REALM="${KC_REALM:-acme-org}"

MOBILE_CLIENT_ID="${MOBILE_CLIENT_ID:-mobile-app}"

BFF_CLIENT_ID="${BFF_CLIENT_ID:-mobile-bff}"
BFF_CLIENT_SECRET="${BFF_CLIENT_SECRET:-2teuKRAHFFST9xk7VzlUwyPHk7JqN68z}"

TARGET_AUDIENCE="${TARGET_AUDIENCE:-orders-api}"

USERNAME="${USERNAME:-alice}"
PASSWORD="${PASSWORD:-password}"

# Optional downstream API test
DOWNSTREAM_URL="${DOWNSTREAM_URL:-}"

# ===== Derived config ==========================================================

TOKEN_ENDPOINT="${KC_BASE_URL}/realms/${KC_REALM}/protocol/openid-connect/token"

# ===== Helpers =================================================================

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

jwt_payload() {
  local token="$1"
  local payload

  payload="$(echo "$token" | cut -d '.' -f2)"

  # base64url -> base64
  payload="${payload//-/+}"
  payload="${payload//_//}"

  # pad base64
  case $((${#payload} % 4)) in
    2) payload="${payload}==" ;;
    3) payload="${payload}=" ;;
  esac

  echo "$payload" | base64 -d 2>/dev/null | jq .
}

print_claims_summary() {
  local label="$1"
  local token="$2"

  echo
  echo "=============================================================================="
  echo "$label"
  echo "=============================================================================="

  jwt_payload "$token" | jq '{
    iss,
    sub,
    preferred_username,
    azp,
    aud,
    scope,
    realm_access,
    resource_access,
    exp,
    iat
  }'
}

assert_jwt_claims() {
  local token="$1"

  echo
  echo "Checking exchanged token claims..."

  local payload
  payload="$(jwt_payload "$token")"

  echo "$payload" | jq -e --arg aud "$TARGET_AUDIENCE" '
    if (.aud | type) == "array" then
      .aud | index($aud)
    else
      .aud == $aud
    end
  ' >/dev/null || {
    echo "ERROR: exchanged token does not contain expected audience: ${TARGET_AUDIENCE}" >&2
    exit 1
  }

  echo "$payload" | jq -e --arg azp "$BFF_CLIENT_ID" '.azp == $azp' >/dev/null || {
    echo "ERROR: exchanged token azp is not ${BFF_CLIENT_ID}" >&2
    exit 1
  }

  echo "$payload" | jq -e '.sub != null and .sub != ""' >/dev/null || {
    echo "ERROR: exchanged token has no user subject" >&2
    exit 1
  }

  echo "OK: exchanged token has expected aud, azp, and sub."
}

# ===== Preconditions ===========================================================

require_cmd curl
require_cmd jq
require_cmd base64

echo "Using token endpoint:"
echo "  ${TOKEN_ENDPOINT}"

# ===== Step 1: Get user token as mobile app ===================================

echo
echo "Requesting user token via password grant as ${MOBILE_CLIENT_ID}..."

USER_TOKEN_RESPONSE="$(
  curl -sS -X POST "${TOKEN_ENDPOINT}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "client_id=${MOBILE_CLIENT_ID}" \
    --data-urlencode "username=${USERNAME}" \
    --data-urlencode "password=${PASSWORD}"
)"

if echo "$USER_TOKEN_RESPONSE" | jq -e '.error' >/dev/null; then
  echo "ERROR: failed to get user token:"
  echo "$USER_TOKEN_RESPONSE" | jq .
  exit 1
fi

USER_ACCESS_TOKEN="$(echo "$USER_TOKEN_RESPONSE" | jq -r '.access_token')"

if [[ -z "$USER_ACCESS_TOKEN" || "$USER_ACCESS_TOKEN" == "null" ]]; then
  echo "ERROR: no access_token in user token response"
  echo "$USER_TOKEN_RESPONSE" | jq .
  exit 1
fi

print_claims_summary "USER ACCESS TOKEN issued to mobile-app" "$USER_ACCESS_TOKEN"

# ===== Step 2: Exchange user token as BFF =====================================

echo
echo "Exchanging user token as ${BFF_CLIENT_ID} for audience ${TARGET_AUDIENCE}..."

EXCHANGED_TOKEN_RESPONSE="$(
  curl -sS -X POST "${TOKEN_ENDPOINT}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -u "${BFF_CLIENT_ID}:${BFF_CLIENT_SECRET}" \
    --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
    --data-urlencode "subject_token=${USER_ACCESS_TOKEN}" \
    --data-urlencode "subject_token_type=urn:ietf:params:oauth:token-type:access_token" \
    --data-urlencode "requested_token_type=urn:ietf:params:oauth:token-type:access_token" \
    --data-urlencode "audience=${TARGET_AUDIENCE}"
)"

if echo "$EXCHANGED_TOKEN_RESPONSE" | jq -e '.error' >/dev/null; then
  echo "ERROR: token exchange failed:"
  echo "$EXCHANGED_TOKEN_RESPONSE" | jq .
  exit 1
fi

EXCHANGED_ACCESS_TOKEN="$(echo "$EXCHANGED_TOKEN_RESPONSE" | jq -r '.access_token')"

if [[ -z "$EXCHANGED_ACCESS_TOKEN" || "$EXCHANGED_ACCESS_TOKEN" == "null" ]]; then
  echo "ERROR: no access_token in token exchange response"
  echo "$EXCHANGED_TOKEN_RESPONSE" | jq .
  exit 1
fi

print_claims_summary "EXCHANGED ACCESS TOKEN issued via mobile-bff for orders-api" "$EXCHANGED_ACCESS_TOKEN"

# ===== Step 3: Validate expected claims =======================================

assert_jwt_claims "$EXCHANGED_ACCESS_TOKEN"

echo
echo "Checking legacy realm-role model..."

jwt_payload "$EXCHANGED_ACCESS_TOKEN" | jq -e '
  .realm_access.roles | index("ORDERS_READ")
' >/dev/null && echo "OK: user role ORDERS_READ found." \
  || echo "WARN: user role ORDERS_READ not found in exchanged token."

jwt_payload "$EXCHANGED_ACCESS_TOKEN" | jq -e '
  .realm_access.roles | index("SVC_MOBILE_BFF_CALL_ORDERS_API")
' >/dev/null && echo "OK: service-call role SVC_MOBILE_BFF_CALL_ORDERS_API found." \
  || echo "WARN: service-call role SVC_MOBILE_BFF_CALL_ORDERS_API not found in exchanged token."

echo
echo "Suggested downstream authorization rule:"
echo "  aud contains ${TARGET_AUDIENCE}"
echo "  azp == ${BFF_CLIENT_ID}"
echo "  realm_access.roles contains ORDERS_READ"
echo "  and either:"
echo "    realm_access.roles contains SVC_MOBILE_BFF_CALL_ORDERS_API"
echo "    OR ${BFF_CLIENT_ID} is allow-listed as backend caller"

# ===== Step 4: Optional downstream call =======================================

if [[ -n "$DOWNSTREAM_URL" ]]; then
  echo
  echo "Calling downstream API:"
  echo "  ${DOWNSTREAM_URL}"

  curl -i -sS "${DOWNSTREAM_URL}" \
    -H "Authorization: Bearer ${EXCHANGED_ACCESS_TOKEN}" \
    -H "Accept: application/json"
else
  echo
  echo "DOWNSTREAM_URL not set; skipping downstream API call."
fi

echo
echo "Done."