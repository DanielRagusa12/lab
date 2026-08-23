#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
terraform_dir=${1:-"$(dirname -- "$script_dir")"}
metadata="$terraform_dir/.terraform/terraform.tfstate"

if [[ ! -f "$metadata" ]]; then
    printf 'tfbackend: no initialized Terraform metadata found in %s\n' "$terraform_dir" >&2
    printf 'Run terraform init, or pass the Terraform directory: %s <directory>\n' "$0" >&2
    exit 1
fi

python3 - "$metadata" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    backend = json.load(f).get("backend")

if not backend:
    raise SystemExit("tfbackend: backend metadata is missing")

backend_type = backend.get("type", "unknown")
config = backend.get("config") or {}
print(f"type: {backend_type}")

if backend_type == "cloud":
    workspaces = config.get("workspaces") or {}
    print(f"hostname: {config.get('hostname') or 'app.terraform.io'}")
    print(f"organization: {config.get('organization') or '(unset)'}")
    print(f"workspace: {workspaces.get('name') or '(unset)'}")
PY
