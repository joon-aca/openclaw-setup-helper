# OpenClaw Quickstart — Ubuntu Server

> Get OpenClaw running on a fresh Ubuntu box with Tailscale, a gateway, and your chat channels wired up. Shouldn't take more than a coffee break.

---

## What You'll End Up With

- OpenClaw gateway running as a systemd user service (survives logout/reboot)
- Tailscale serving HTTPS to your gateway — no port forwarding, no certs to manage
- Chat channels (Telegram, Slack, Discord, etc.) connected and ready
- AI provider configured (Claude, OpenAI, Azure, Ollama, whatever you've got)
- Skills and web tools enabled

```
Your phone (Telegram/Slack/etc.)
    │
    ▼
Tailscale HTTPS  ──▸  OpenClaw Gateway  ──▸  AI Provider
                          │
                          ├── Skills (web search, tools, etc.)
                          ├── Agents (background work)
                          └── Channels (Telegram, Slack, Discord, …)
```

---

## Prerequisites

- Ubuntu 22.04+ (arm64 or amd64)
- A user account with sudo
- Node.js 22+
- At least one AI provider key (Claude, OpenAI, Azure AI Foundry, etc.)
- Bot tokens for your chat channels (Telegram from @BotFather, Slack app/bot tokens, etc.)

---

## The Fast Way

The setup script collects your keys upfront, then handles all the installs and config non-interactively.

```bash
git clone https://github.com/openclaw/openclaw.git /opt/openclaw
cd /opt/openclaw
chmod +x openclaw_setup.sh
./openclaw_setup.sh
```

It will prompt you for API keys first (enter to skip any you don't have yet), then:

1. Installs OpenClaw via the official installer
2. Sets up Tailscale (interactive login if no `TAILSCALE_AUTHKEY`)
3. Optionally installs Homebrew + skill dependencies
4. Generates a gateway token
5. Configures the gateway (loopback bind + Tailscale Serve)
6. Enables systemd lingering
7. Starts the gateway service

When it finishes, run the interactive wizard to configure channels and your AI provider:

```bash
set -a; source ~/.openclaw/.env; set +a
openclaw configure
```

### Env knobs

Skip stuff you don't need or already have:

| Variable | Default | What it does |
|----------|---------|-------------|
| `TAILSCALE_AUTHKEY` | _(empty)_ | Pre-auth key — skips interactive Tailscale login |
| `TAILSCALE_HOSTNAME` | `lando` | Your node's Tailscale hostname |
| `OPENCLAW_PORT` | `18789` | Gateway listen port |
| `SKIP_TAILSCALE` | `0` | Set `1` to skip Tailscale entirely |
| `SKIP_BREW` | `0` | Set `1` to skip Homebrew + skill deps |
| `RUN_WIZARD` | `0` | Set `1` to launch `openclaw onboard` at the end |

Example — headless provisioning with everything pre-set:

```bash
TAILSCALE_AUTHKEY="tskey-auth-..." \
SKIP_BREW=1 \
RUN_WIZARD=1 \
./openclaw_setup.sh
```

---

## The Manual Way

If you'd rather understand each step (or the script isn't your style):

### 1. Install OpenClaw

```bash
curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
```

### 2. Set up your secrets

Create `~/.openclaw/.env` (chmod 600) with whatever keys you have:

```bash
BRAVE_API_KEY=your-brave-key
TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
# Add any others: SLACK_APP_TOKEN, SLACK_BOT_TOKEN, OPENAI_API_KEY, etc.
```

### 3. Configure the gateway

```bash
openclaw config set gateway.mode local
openclaw config set gateway.port 18789
openclaw config set gateway.bind loopback
openclaw config set gateway.auth.mode token
openclaw config set gateway.tailscale.mode serve
openclaw config set tools.web.search.enabled true
openclaw config set tools.web.fetch.enabled true
```

### 4. Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sudo sh
sudo systemctl enable --now tailscaled
sudo tailscale up --hostname your-hostname
```

### 5. Enable lingering + start the gateway

```bash
sudo loginctl enable-linger "$USER"

# Source env so the gateway sees your tokens
set -a; source ~/.openclaw/.env; set +a

openclaw gateway install \
  --port 18789 \
  --runtime node \
  --token "$OPENCLAW_GATEWAY_TOKEN" \
  --force

openclaw gateway start
```

### 6. Run the wizard

```bash
openclaw configure
```

This walks you through channel setup, AI provider selection, and skills.

---

## Custom AI Providers (Azure AI Foundry, Ollama, etc.)

If you're using an OpenAI-compatible provider (Azure AI Foundry, Together AI, Ollama, etc.), you can add it directly to `~/.openclaw/openclaw.json` under `models.providers`:

```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "my-provider": {
        "baseUrl": "https://your-endpoint.example.com/openai/v1/",
        "api": "openai-completions",
        "apiKey": "your-api-key",
        "models": [
          {
            "id": "model-name",
            "name": "Model Name (My Provider)",
            "contextWindow": 131072,
            "maxTokens": 8192,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "reasoning": false
          }
        ]
      }
    }
  }
}
```

Or use the wizard: `openclaw configure` and pick **Custom Provider**.

---

## Verify Everything Works

```bash
openclaw doctor              # checks config, deps, connectivity
openclaw gateway status      # gateway health
openclaw channels status     # channel connectivity
sudo tailscale serve status  # Tailscale HTTPS status
```

---

## Day-to-Day

```bash
openclaw gateway start       # start the gateway
openclaw gateway stop        # stop it
openclaw gateway restart     # restart after config changes
openclaw gateway status      # check it's alive
openclaw channels status --probe  # deep-check channel connections
```

Logs live at `/tmp/openclaw-gateway.log` (systemd service) or wherever your service config points.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `openclaw: command not found` | Re-run the installer, or add `~/.npm-global/bin` to your PATH |
| Gateway won't start | Check `openclaw doctor`, verify token in env matches what gateway expects |
| Tailscale Serve not working | `sudo tailscale serve status`, make sure gateway is bound to loopback |
| Channel shows "not configured" | Run `openclaw configure` to add the bot token |
| Custom provider gives 404 | Check your base URL — if it already has `/v1`, don't let the wizard mangle it |
| Keys not picked up | Source the env: `set -a; source ~/.openclaw/.env; set +a` then restart |

---

## Docs

- [OpenClaw Documentation](https://docs.openclaw.ai)
- [Gateway + Tailscale](https://docs.openclaw.ai/gateway/tailscale)
- [Channels](https://docs.openclaw.ai/channels)
- [Skills](https://docs.openclaw.ai/skills)
- [Web Tools](https://docs.openclaw.ai/tools/web)
