# Moltbot + CLIProxyAPIPlus: Use Your Claude Max Subscription

Run [Moltbot](https://molt.bot/) (formerly Clawdbot) on an EC2 instance using your **Claude Max/Pro subscription** instead of paying for Anthropic API keys.

This setup deploys [CLIProxyAPIPlus](https://github.com/router-for-me/CLIProxyAPIPlus) alongside Moltbot on the same server. CLIProxyAPIPlus handles OAuth authentication with your Claude subscription and exposes a local API that Moltbot routes through — no API credits needed.

## Architecture

```
WhatsApp/Telegram/Discord
        │
        ▼
   Moltbot Gateway (:18789)
        │
        ▼
  CLIProxyAPIPlus (:8317, localhost only)
        │
        ▼
  Claude OAuth (your Max/Pro subscription)
```

## What You Need

1. **AWS EC2 instance** — Ubuntu 24.04 LTS ARM64, `t4g.small` (~$14/mo)
2. **Claude Max or Pro subscription** — for OAuth authentication
3. **SSH key pair** — for EC2 access

## Quick Start

### 1. Launch EC2

| Setting | Value |
|---------|-------|
| AMI | Ubuntu 24.04 LTS ARM64 |
| Instance type | `t4g.small` (2 vCPU, 2GB RAM) |
| Storage | 20GB gp3 |
| Security Group | SSH (port 22) from your IP only |

Allocate an **Elastic IP** so your address survives reboots.

### 2. Upload and run the setup script

```bash
# Upload
scp -i ~/.ssh/your-key.pem setup.sh ubuntu@<your-ec2-ip>:~/

# SSH in and run
ssh -i ~/.ssh/your-key.pem ubuntu@<your-ec2-ip>
chmod +x setup.sh
./setup.sh
```

### 3. Authenticate Claude OAuth

The setup script will prompt you to authenticate. On your **local machine**, set up the SSH tunnel it tells you to, then open the OAuth URL in your browser and sign in with your Claude account.

### 4. Connect WhatsApp

```bash
moltbot channels login whatsapp
# Scan the QR code with your phone
```

### 5. Access the dashboard

From your local machine:
```bash
ssh -L 18789:127.0.0.1:18789 -i ~/.ssh/your-key.pem ubuntu@<your-ec2-ip>
```
Then open http://127.0.0.1:18789/

## Switching Models

```bash
# List available models
moltbot models list

# Switch to Opus 4.5
moltbot models set anthropic/claude-opus-4-5

# Switch to Sonnet 4.5
moltbot models set anthropic/claude-sonnet-4-5
```

All models go through your subscription — no API costs.

## Available Model Aliases

| Model | Full Name |
|-------|-----------|
| `claude-opus-4-5` | `claude-opus-4-5-20251101` |
| `claude-sonnet-4-5` | `claude-sonnet-4-5-20250929` |
| `claude-haiku-4-5` | `claude-haiku-4-5-20251001` |
| `claude-opus-4-1` | `claude-opus-4-1-20250805` |
| `claude-opus-4` | `claude-opus-4-20250514` |
| `claude-sonnet-4` | `claude-sonnet-4-20250514` |
| `claude-3-7-sonnet` | `claude-3-7-sonnet-20250219` |
| `claude-3-5-haiku` | `claude-3-5-haiku-20241022` |

## Files

| File | Description |
|------|-------------|
| `setup.sh` | Full setup script (installs everything, builds proxy, configures services) |
| `config/cli-proxy-api.yaml` | CLIProxyAPIPlus config template (hardened, localhost-only) |
| `config/models.json` | Moltbot agent model routing config |
| `config/cli-proxy-api.service` | Systemd service for the proxy |
| `config/clawdbot.service` | Systemd service for Moltbot |
| `scripts/open-dashboard.sh` | Local helper to SSH tunnel + open dashboard |

## Security

- CLIProxyAPIPlus binds to `127.0.0.1` only — never exposed to the internet
- UFW firewall allows only SSH (port 22)
- API keys and management secrets are randomly generated during setup
- OAuth credentials stored with `chmod 600`
- Original Anthropic API key backed up at `/etc/clawdbot/env.backup`
- fail2ban protects SSH (5 retries, 1-hour ban)

## Monthly Cost

| Resource | Cost |
|----------|------|
| EC2 t4g.small | ~$12 |
| 20GB gp3 EBS | ~$1.60 |
| Elastic IP | Free (attached) |
| **Total infra** | **~$14/month** |
| Claude Max subscription | $100/month (you already have this) |
| Anthropic API | **$0** |

## Rollback to API Key

If you want to stop using the proxy and go back to the Anthropic API:

```bash
sudo cp /etc/clawdbot/env.backup /etc/clawdbot/env
moltbot config unset env.ANTHROPIC_BASE_URL
rm ~/.clawdbot/agents/main/agent/models.json
sudo systemctl restart clawdbot
```

## Credits

- [Moltbot](https://molt.bot/) — the AI assistant
- [CLIProxyAPIPlus](https://github.com/router-for-me/CLIProxyAPIPlus) — the proxy engine
- [VibeProxy](https://github.com/automazeio/vibeproxy) — the macOS GUI wrapper (this setup replaces it for Linux servers)

## License

MIT
