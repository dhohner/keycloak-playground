#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

BASE_COMPOSE_FILE="${BASE_COMPOSE_FILE:-${PROJECT_ROOT}/compose.yaml}"
CONFIG_CLI_COMPOSE_FILE="${CONFIG_CLI_COMPOSE_FILE:-${PROJECT_ROOT}/config-as-code/keycloak-config-cli/compose.yaml}"

usage() {
  cat <<'USAGE'
Usage: scripts/compose.sh [options] [compose-args...]
       scripts/compose.sh <command>

Options:
  --config-cli                 Include keycloak-config-cli compose file
  --file <path>, -f <path>     Add compose file
  --debug                      Enable debug logs for supported one-shot commands
  --no-default-file            Do not add compose.yaml automatically
  -h, --help                   Show help

Commands:
  start                        Start Keycloak and Postgres
  stop                         Stop Keycloak and Postgres
  logs [service...]            Follow logs; defaults to keycloak
  config-apply [--debug]       Apply keycloak-config-cli realm configuration via one-shot run
  config-logs                  Show keycloak-config-cli logs
  version                      Show selected compose runtime version

Env:
  COMPOSE_CMD                  Override runtime, e.g. "docker compose"
  BASE_COMPOSE_FILE            Override base compose file
  CONFIG_CLI_COMPOSE_FILE      Override config-cli compose file
  KEYCLOAK_CONFIG_CLI_COMPONENT_LOG_LEVEL Component/action log level for config-cli
  KEYCLOAK_CONFIG_CLI_DEBUG     Set true to enable Spring Boot debug mode
USAGE
}

detect_compose_runtime() {
  COMPOSE_RUNTIME=()

  if [[ -n "${COMPOSE_CMD:-}" ]]; then
    read -r -a COMPOSE_RUNTIME <<< "$COMPOSE_CMD"
    return 0
  fi

  if command -v podman-compose >/dev/null 2>&1; then
    COMPOSE_RUNTIME=(podman-compose)
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE_RUNTIME=(docker compose)
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_RUNTIME=(docker-compose)
    return 0
  fi

  fatal "No Compose runtime found. Install podman-compose, Docker Compose v2, or docker-compose."
}

run_compose() {
  local -a COMPOSE_RUNTIME
  detect_compose_runtime
  exec "${COMPOSE_RUNTIME[@]}" "$@"
}

run_compose_stream() {
  local -a COMPOSE_RUNTIME
  detect_compose_runtime
  "${COMPOSE_RUNTIME[@]}" "$@"
}

format_logs() {
  awk '
    BEGIN {
      svc_colors[0]="\033[36m"; svc_colors[1]="\033[32m"; svc_colors[2]="\033[35m"; svc_colors[3]="\033[33m"
      dim="\033[2m"; reset="\033[0m"; red="\033[31m"; yellow="\033[33m"; blue="\033[34m"; gray="\033[90m"
    }
    {
      line=$0
      pipe=index(line, "|")
      if (pipe > 0) {
        svc=substr(line, 1, pipe - 1)
        msg=substr(line, pipe + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", svc)
        gsub(/^[[:space:]]+/, "", msg)
      } else {
        svc="keycloak"; msg=line
      }

      if (!(svc in seen)) { seen[svc]=count % 4; count++ }
      prefix=sprintf("%s[%s]%s ", svc_colors[seen[svc]], svc, reset)

      # Preserve native ANSI from Keycloak. If none is present, lightly color common levels.
      if (index(msg, "\033[") == 0) {
        gsub(/ERROR/, red "ERROR" reset, msg)
        gsub(/WARN /, yellow "WARN " reset, msg)
        gsub(/INFO /, blue "INFO " reset, msg)
        gsub(/DEBUG/, gray "DEBUG" reset, msg)
        gsub(/TRACE/, gray "TRACE" reset, msg)
      }

      printf "%s%s\n", prefix, msg
      fflush()
    }
  '
}
run_logs() {
  local -a compose_args=("$@")
  run_compose_stream "${compose_args[@]}" 2>&1 | format_logs
}

main() {
  local include_default_file=true
  local include_config_cli=false
  local -a files=()
  local -a args=()
  local stream_logs=false
  local debug=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config-cli)
        include_config_cli=true
        shift
        ;;
      --file|-f)
        [[ $# -ge 2 ]] || fatal "$1 requires a path"
        files+=("$2")
        shift 2
        ;;
      --debug)
        debug=true
        shift
        ;;
      --no-default-file)
        include_default_file=false
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      start)
        args=(up -d)
        shift
        break
        ;;
      stop)
        args=(down)
        shift
        break
        ;;
      logs)
        shift
        stream_logs=true
        if [[ $# -gt 0 ]]; then
          args=(logs -f --tail "${LOG_TAIL:-200}" -n "$@")
        else
          args=(logs -f --tail "${LOG_TAIL:-200}" -n keycloak)
        fi
        set --
        break
        ;;
      config-apply)
        include_config_cli=true
        shift
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --debug) debug=true; shift ;;
            *) fatal "unknown config-apply option: $1" ;;
          esac
        done
        if [[ "$debug" == true ]]; then
          args=(run --rm \
            -e LOGGING_LEVEL_DE_ADORSYS_KEYCLOAK_CONFIG=debug \
            keycloak-config-cli)
        else
          args=(run --rm keycloak-config-cli)
        fi
        break
        ;;
      config-logs)
        include_config_cli=true
        stream_logs=true
        args=(logs -f --tail "${LOG_TAIL:-200}" -n keycloak-config-cli)
        shift
        break
        ;;
      *)
        args=("$@")
        set --
        break
        ;;
    esac
  done

  [[ ${#args[@]} -gt 0 ]] || { usage; exit 2; }

  local -a compose_args=()
  if [[ "$include_default_file" == true ]]; then
    compose_args+=(-f "$BASE_COMPOSE_FILE")
  fi
  if [[ ${#files[@]} -gt 0 ]]; then
    for file in "${files[@]}"; do
      compose_args+=(-f "$file")
    done
  fi
  if [[ "$include_config_cli" == true ]]; then
    compose_args+=(-f "$CONFIG_CLI_COMPOSE_FILE")
  fi

  if [[ "$stream_logs" == true ]]; then
    run_logs "${compose_args[@]}" "${args[@]}"
  else
    run_compose "${compose_args[@]}" "${args[@]}"
  fi
}

main "$@"
