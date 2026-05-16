# Config as Code

Manages Keycloak realms, clients, roles, and other settings from files instead of the Admin Console.

## Available tools

| folder                 | tool                          | status                            | best for                                   |
| ---------------------- | ----------------------------- | --------------------------------- | ------------------------------------------ |
| `keycloak-config-cli/` | adorsys `keycloak-config-cli` | active                            | YAML-driven realm and client configuration |
| `terraform/`           | Terraform Keycloak provider   | **planned — not yet implemented** | stateful infra-style config management     |

## Ownership rule

Assign exactly one tool as owner for each Keycloak object it manages. Two tools managing the same object will overwrite each other or fight over defaults.

**Safe:**

```text
keycloak-config-cli  →  realm acme-org
Terraform            →  realm example-org  (separate realm)
```

**Risky:**

```text
keycloak-config-cli and Terraform both manage client billing-worker
```

## Compose structure

| file                                              | purpose                                  |
| ------------------------------------------------- | ---------------------------------------- |
| `compose.yaml`                                    | base Keycloak + Postgres stack           |
| `config-as-code/keycloak-config-cli/compose.yaml` | optional one-shot adorsys import service |

Run the config import service alongside the base stack by merging Compose files:

```bash
docker compose \
  -f compose.yaml \
  -f config-as-code/keycloak-config-cli/compose.yaml \
  up
```

See [`keycloak-config-cli/README.md`](keycloak-config-cli/README.md) for setup and usage.
