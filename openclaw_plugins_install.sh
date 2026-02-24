#!/usr/bin/env bash
set -euo pipefail

log(){ printf "\n\033[1m==> %s\033[0m\n" "$*"; }
die(){ printf "\n\033[31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

is_openclaw_dir() {
  [[ -f "$1/package.json" ]] && grep -q '"openclaw"' "$1/package.json" 2>/dev/null
}

ensure_openclaw_dir() {
  local script_path
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  local script_dir
  script_dir="$(dirname "$script_path")"

  if is_openclaw_dir "$script_dir"; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    die "Not running from an OpenClaw directory. Re-run from your OpenClaw checkout."
  fi

  echo
  echo "This script isn't inside an OpenClaw directory."
  echo "Where is your OpenClaw checkout? (relative or absolute path)"
  printf "> "
  local oc_dir=""
  IFS= read -r oc_dir

  oc_dir="$(cd "$oc_dir" 2>/dev/null && pwd)" || die "Directory not found: $oc_dir"

  if ! is_openclaw_dir "$oc_dir"; then
    die "$oc_dir doesn't look like an OpenClaw checkout"
  fi

  local link_path="$oc_dir/$(basename "$script_path")"
  if [[ -e "$link_path" && ! -L "$link_path" ]]; then
    die "$link_path already exists and is not a symlink"
  fi
  ln -sf "$script_path" "$link_path"
  log "Linked into $oc_dir — re-executing from there"

  exec "$link_path" "$@"
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
  ensure_openclaw_dir "$@"

  need openclaw
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

  local id
  for spec in "${specs[@]}"; do
    id="$(plugin_id_from_spec "$spec")"

    log "Installing plugin: ${spec}"
    openclaw plugins install "$spec" --pin

    log "Enabling plugin: ${id}"
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
  echo "  - Configure the channel under channels.<id> (NOT plugins.entries) for channel plugins."
  echo "  - Then: openclaw gateway restart"
}

main "$@"

