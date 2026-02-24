#!/usr/bin/env bash
set -euo pipefail

log(){ printf "\n\033[1m==> %s\033[0m\n" "$*"; }
die(){ printf "\n\033[31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }
sudo_if_needed(){ if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then sudo "$@"; else "$@"; fi; }

need(){ command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

install_node22_if_missing() {
  if command -v npm >/dev/null 2>&1; then
    log "npm present: $(npm -v)"
    return
  fi

  log "npm missing; installing Node.js 22.x (includes npm)"
  sudo_if_needed apt-get update -y
  sudo_if_needed apt-get install -y --no-install-recommends ca-certificates curl gnupg

  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo_if_needed -E bash -
  sudo_if_needed apt-get install -y nodejs

  log "node: $(node -v)  npm: $(npm -v)"
}

plugin_id_from_spec() {
  # @openclaw/msteams -> msteams
  # @openclaw/voice-call -> voice-call
  # matrix -> matrix
  local spec="$1"
  spec="${spec##*/}"
  spec="${spec#@}"
  echo "$spec"
}

main() {
  need openclaw

  install_node22_if_missing
  need npm

  # Default set: "official + commonly useful"
  # (You can override by passing args.)
  local specs=("$@")
  if [[ ${#specs[@]} -eq 0 ]]; then
    specs=(
      "@openclaw/matrix"
      "@openclaw/msteams"
      "@openclaw/tlon"
      "@openclaw/twitch"
      "@openclaw/zalouser"
      "@openclaw/voice-call"
    )
  fi

  log "Before: plugins list"
  openclaw plugins list || true

  for spec in "${specs[@]}"; do
    local id
    id="$(plugin_id_from_spec "$spec")"

    log "Installing plugin: ${spec}"
    # Docs: supports npm specs; --pin stores exact resolved name@version. :contentReference[oaicite:5]{index=5}
    openclaw plugins install "$spec" --pin

    log "Enabling plugin id: ${id}"
    # Bundled plugins may be disabled by default; installed plugins are usually enabled automatically,
    # but enabling is idempotent. :contentReference[oaicite:6]{index=6}
    openclaw plugins enable "$id" || true
  done

  log "Plugin doctor"
  openclaw plugins doctor || true

  log "Restarting gateway (so plugins load)"
  openclaw gateway restart || (openclaw gateway start || true)

  log "After: plugins list"
  openclaw plugins list || true

  echo
  echo "Next:"
  echo "  - Configure the channel under channels.<id> (NOT plugins.entries) for channel plugins. :contentReference[oaicite:7]{index=7}"
  echo "  - Then: openclaw gateway restart"
}

main "$@"

