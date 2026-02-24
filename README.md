# OpenClaw Setup Helper

Helper scripts for deploying and configuring [OpenClaw](https://github.com/openclaw/openclaw) on an Ubuntu server. These live alongside (or inside) your OpenClaw checkout and automate the tedious parts of initial setup and plugin installation.

## Scripts

| Script | Purpose |
|--------|---------|
| `openclaw_setup_helper.sh` | Full server setup: secrets, Tailscale, Homebrew/skills, gateway config, onboarding wizard |
| `openclaw_plugins_install.sh` | Install and enable community/extra plugins |

## Quick Start

Clone this repo into your OpenClaw directory (or symlink the scripts there):

```bash
# If you already have an OpenClaw checkout:
cd /opt/openclaw
git clone https://github.com/openclaw/openclaw-setup-helper .setup-helper
ln -s .setup-helper/openclaw_setup_helper.sh .
ln -s .setup-helper/openclaw_plugins_install.sh .

# Run the setup
chmod +x openclaw_setup_helper.sh
./openclaw_setup_helper.sh
```

The script will:

1. Prompt for all API keys upfront (enter to skip any)
2. Install OpenClaw (if not already present)
3. Set up Tailscale
4. Optionally install Homebrew + skill dependencies
5. Generate a gateway token and apply config
6. Run `openclaw onboard` to configure channels, AI provider, and start the gateway daemon

## Env Knobs

Override defaults by exporting before running:

| Variable | Default | What it does |
|----------|---------|-------------|
| `TAILSCALE_AUTHKEY` | _(empty)_ | Pre-auth key — skips interactive Tailscale login |
| `TAILSCALE_HOSTNAME` | `lando` | Tailscale node hostname |
| `OPENCLAW_PORT` | `18789` | Gateway listen port |
| `SKIP_TAILSCALE` | `0` | Set `1` to skip Tailscale entirely |
| `SKIP_BREW` | `0` | Set `1` to skip Homebrew + skill deps |

Example — headless with pre-set Tailscale:

```bash
TAILSCALE_AUTHKEY="tskey-auth-..." SKIP_BREW=1 ./openclaw_setup_helper.sh
```

## Installing Plugins

After setup, install community plugins:

```bash
./openclaw_plugins_install.sh
```

This installs the default set (Matrix, MS Teams, Tlon, Twitch, Zalo, Voice Call). Pass specific package names to override:

```bash
./openclaw_plugins_install.sh @openclaw/matrix @openclaw/voice-call
```

## Docs

- [OpenClaw Documentation](https://docs.openclaw.ai)
- [Gateway + Tailscale](https://docs.openclaw.ai/gateway/tailscale)
- [Channels](https://docs.openclaw.ai/channels)
- [Skills](https://docs.openclaw.ai/skills)
