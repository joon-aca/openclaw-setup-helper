#!/usr/bin/env bash
set -euo pipefail
umask 077

############################################
# openclaw_setup.sh (Ubuntu server)
#
# Collects all secrets interactively FIRST,
# then runs installs + config non-interactively.
#
# Outputs:
#   ~/.openclaw/.env          (secrets + gateway token)
#
# Optional env knobs:
#   TAILSCALE_AUTHKEY="tskey-..."   # skip interactive tailscale login
#   TAILSCALE_HOSTNAME="lando"
#   OPENCLAW_PORT="18789"
#   SKIP_TAILSCALE=0               # set 1 to skip tailscale entirely
#   SKIP_BREW=0                    # set 1 to skip homebrew + skill deps
#   RUN_WIZARD=0                   # set 1 to run openclaw onboard at end
############################################

log()  { printf "\n\033[1m==> %s\033[0m\n" "$*"; }
warn() { printf "\n\033[33mWARN:\033[0m %s\n" "$*" >&2; }
die()  { printf "\n\033[31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-lando}"
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
SKIP_TAILSCALE="${SKIP_TAILSCALE:-0}"
SKIP_BREW="${SKIP_BREW:-0}"
RUN_WIZARD="${RUN_WIZARD:-0}"

STATE_DIR="$HOME/.openclaw"
ENV_FILE="$STATE_DIR/.env"

sudo_if_needed() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then sudo "$@"; else "$@"; fi
}

apt_install() {
  sudo_if_needed apt-get update -y
  sudo_if_needed apt-get install -y --no-install-recommends "$@"
}

ensure_files() {
  mkdir -p "$STATE_DIR"
  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

write_env_kv() {
  local k="$1" v="${2:-}"
  [[ -z "$v" ]] && return 0
  if grep -qE "^${k}=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s#^${k}=.*#${k}=${v}#g" "$ENV_FILE"
  else
    printf "%s=%s\n" "$k" "$v" >> "$ENV_FILE"
  fi
}

############################################
# Interactive prompts — all upfront
############################################
ask_secret() {
  local var="$1" label="$2" url="$3"

  # Already in env file? Skip.
  if grep -qE "^${var}=" "$ENV_FILE" 2>/dev/null; then
    log "$var already set in $ENV_FILE — skipping"
    return 0
  fi

  # Already exported? Persist and skip.
  if [[ -n "${!var:-}" ]]; then
    write_env_kv "$var" "${!var}"
    return 0
  fi

  # No TTY? Can't prompt.
  if [[ ! -t 0 ]]; then
    warn "No TTY; skipping $var. Add it later to $ENV_FILE"
    return 0
  fi

  echo
  echo "------------------------------------------------------------"
  echo "$label"
  echo "  $url"
  echo "Paste value (Enter to skip):"
  printf "> "
  local val=""
  IFS= read -r -s val
  printf "\n"

  if [[ -z "$val" ]]; then
    warn "Skipped $var"
    return 0
  fi

  write_env_kv "$var" "$val"
}

collect_secrets() {
  log "Collecting secrets (all prompts now, installs after)"

  ask_secret "BRAVE_API_KEY" \
    "Brave Search API key (enables web_search)" \
    "https://docs.openclaw.ai/tools/web"

  ask_secret "TELEGRAM_BOT_TOKEN" \
    "Telegram bot token (from @BotFather)" \
    "https://docs.openclaw.ai/channels/telegram"

  ask_secret "SLACK_APP_TOKEN" \
    "Slack App token — Socket Mode (xapp-...)" \
    "https://docs.openclaw.ai/channels/slack"

  ask_secret "SLACK_BOT_TOKEN" \
    "Slack Bot token (xoxb-...)" \
    "https://docs.openclaw.ai/channels/slack"

  ask_secret "GOOGLE_PLACES_API_KEY" \
    "Google Places API key (optional, for goplaces skill)" \
    "https://docs.openclaw.ai/skills"

  ask_secret "GEMINI_API_KEY" \
    "Gemini API key (optional)" \
    "https://docs.openclaw.ai/skills"

  ask_secret "NOTION_API_KEY" \
    "Notion API key (optional)" \
    "https://docs.openclaw.ai/skills"

  ask_secret "OPENAI_API_KEY" \
    "OpenAI API key (optional)" \
    "https://docs.openclaw.ai/skills"

  ask_secret "ELEVENLABS_API_KEY" \
    "ElevenLabs API key (optional, for TTS)" \
    "https://docs.openclaw.ai/skills"
}

############################################
# Tailscale
############################################
setup_tailscale() {
  [[ "$SKIP_TAILSCALE" == "1" ]] && { log "Skipping Tailscale (SKIP_TAILSCALE=1)"; return 0; }

  if ! command -v tailscale >/dev/null 2>&1; then
    log "Installing Tailscale"
    curl -fsSL https://tailscale.com/install.sh | sudo_if_needed sh
  fi

  sudo_if_needed systemctl enable --now tailscaled

  # Already connected?
  if tailscale ip -4 >/dev/null 2>&1; then
    log "Tailscale already up: $(tailscale ip -4)"
    return 0
  fi

  log "Bringing Tailscale up"
  if [[ -n "$TAILSCALE_AUTHKEY" ]]; then
    sudo_if_needed tailscale up --authkey "$TAILSCALE_AUTHKEY" --hostname "$TAILSCALE_HOSTNAME"
  else
    # This may print a login URL and block — that's expected
    sudo_if_needed tailscale up --hostname "$TAILSCALE_HOSTNAME"
  fi

  tailscale ip -4 >/dev/null 2>&1 || die "tailscale up failed"
  log "Tailscale up: $(tailscale ip -4)"
}

############################################
# Homebrew + skill deps
############################################
setup_brew() {
  [[ "$SKIP_BREW" == "1" ]] && { log "Skipping Homebrew (SKIP_BREW=1)"; return 0; }

  local brew_bin=""
  if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    brew_bin="/home/linuxbrew/.linuxbrew/bin/brew"
  elif command -v brew >/dev/null 2>&1; then
    brew_bin="$(command -v brew)"
  fi

  if [[ -z "$brew_bin" ]]; then
    log "Installing Homebrew (Linuxbrew)"
    apt_install build-essential procps file git
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew_bin="/home/linuxbrew/.linuxbrew/bin/brew"
  fi

  [[ -x "$brew_bin" ]] || die "brew install failed"

  # Wire into PATH for this session
  eval "$("$brew_bin" shellenv)"

  # Persist across logins
  local brew_eval="eval \"\$($brew_bin shellenv)\""
  for rc in "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bashrc"; do
    mkdir -p "$(dirname "$rc")"
    touch "$rc"
    grep -Fqs "$brew_eval" "$rc" || printf "\n%s\n" "$brew_eval" >> "$rc"
  done

  log "Installing skill dependencies"
  brew update
  brew tap steipete/tap   || true
  brew tap Hyaxia/tap     || true
  brew tap xdevplatform/tap || true

  local formulas=(go 1password-cli gogcli himalaya
    steipete/tap/gifgrep steipete/tap/mcporter steipete/tap/wacli
    xdevplatform/tap/xurl Hyaxia/tap/blogwatcher)
  for f in "${formulas[@]}"; do
    brew install "$f" || true
  done
}

############################################
# OpenClaw install + config
############################################
install_openclaw() {
  if command -v openclaw >/dev/null 2>&1; then
    log "openclaw already installed"
    return 0
  fi
  log "Installing OpenClaw"
  curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
  command -v openclaw >/dev/null 2>&1 || die "openclaw install failed"
}

ensure_gateway_token() {
  if grep -qE '^OPENCLAW_GATEWAY_TOKEN=' "$ENV_FILE" 2>/dev/null; then
    log "Gateway token already in env"
    return 0
  fi
  log "Generating gateway token"
  local tok
  tok="$(openssl rand -hex 32)"
  write_env_kv "OPENCLAW_GATEWAY_TOKEN" "$tok"
}

apply_config() {
  log "Applying openclaw config"

  openclaw config set gateway.mode local
  openclaw config set gateway.port "$OPENCLAW_PORT"
  openclaw config set gateway.bind loopback
  openclaw config set gateway.auth.mode token
  # Token lives in env, not in config — the gateway reads OPENCLAW_GATEWAY_TOKEN from env
  openclaw config unset gateway.auth.token 2>/dev/null || true
  openclaw config set gateway.tailscale.mode serve
  openclaw config set gateway.tailscale.resetOnExit false

  openclaw config set tools.web.search.enabled true
  openclaw config set tools.web.fetch.enabled true
}

start_gateway() {
  log "Installing/starting gateway service"

  # Source env so the gateway install picks up the token
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  openclaw gateway install \
    --port "$OPENCLAW_PORT" \
    --runtime node \
    --token "$OPENCLAW_GATEWAY_TOKEN" \
    --force

  openclaw gateway restart || openclaw gateway start || true
  openclaw gateway status || true
}

############################################
# Main — sequenced to avoid hangs
############################################
main() {
  log "Installing base packages"
  apt_install curl ca-certificates jq openssl git

  ensure_files

  # ── Phase 1: all interactive prompts ──
  collect_secrets

  # ── Phase 2: installs (may block on network, not on stdin) ──
  install_openclaw
  setup_tailscale
  setup_brew

  # ── Phase 3: non-interactive config + start ──
  ensure_gateway_token
  apply_config

  log "Enabling systemd lingering"
  sudo_if_needed loginctl enable-linger "$USER"

  start_gateway

  log "Running doctor"
  openclaw doctor || true

  # ── Phase 4: optional wizard ──
  if [[ "$RUN_WIZARD" == "1" ]]; then
    log "Launching wizard with env loaded"
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
    openclaw onboard --install-daemon
  else
    echo
    echo "Setup complete. To run the interactive wizard:"
    echo "  set -a; source ~/.openclaw/.env; set +a; openclaw configure"
    echo
  fi
}

main "$@"
