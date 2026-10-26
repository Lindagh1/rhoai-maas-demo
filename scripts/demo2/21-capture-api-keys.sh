#!/usr/bin/env bash
# Secure local helper: prompts for the two Demo 2 API keys without echoing
# them, then writes them to the expected gitignored files.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/demo2/lib.sh

main_file="$DEMO2_USER_APIKEY_FILE"
ratelimit_file="$SECRETS_DIR/${DEMO2_USER}.ratelimit.apikey"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR" 2>/dev/null || true

prompt_key() {
  local label="$1" value=""
  while true; do
    read -r -s -p "$label" value
    echo
    if [[ -z "$value" ]]; then
      warn "Empty value, please try again."
      continue
    fi
    if [[ "$value" != sk-oai-* ]]; then
      warn "Value does not start with 'sk-oai-'. Re-enter carefully."
      continue
    fi
    printf '%s' "$value"
    return 0
  done
}

echo "=============================================="
echo "Demo 2 — capture API keys locally"
echo "=============================================="
echo "Paste each key when prompted. Input is hidden and nothing is echoed."
echo

MAIN_KEY="$(prompt_key "Main subscription key: ")"
RL_KEY="$(prompt_key "Rate-limit subscription key: ")"

printf '%s\n' "$MAIN_KEY" > "$main_file"
printf '%s\n' "$RL_KEY" > "$ratelimit_file"
chmod 600 "$main_file" "$ratelimit_file"

ok "Saved:"
echo "  $main_file"
echo "  $ratelimit_file"
echo
info "Next step: make demo2-verify"
