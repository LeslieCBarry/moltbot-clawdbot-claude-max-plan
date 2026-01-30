#!/usr/bin/env bash
# =============================================================================
# Moltbot + CLIProxyAPIPlus Setup Script
# =============================================================================
# Deploys Moltbot with CLIProxyAPIPlus on an EC2 instance so you can use
# your Claude Max/Pro subscription instead of paying for API keys.
#
# Tested on: Ubuntu 24.04 LTS ARM64 (t4g.small or larger)
#
# Usage:
#   1. Launch an EC2 instance (Ubuntu 24.04 ARM64, t4g.small, 20GB gp3)
#   2. Upload this script: scp -i <key>.pem setup.sh ubuntu@<ip>:~/
#   3. SSH in and run: chmod +x setup.sh && ./setup.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1" >&2; }

WORKSPACE="${WORKSPACE_DIR:-$HOME/clawd}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.clawdbot}"
PROXY_DIR="$HOME/cli-proxy/CLIProxyAPIPlus"

# =============================================================================
# STEP 1: System Update
# =============================================================================
log "Updating system packages..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# =============================================================================
# STEP 2: Install Dependencies
# =============================================================================
log "Installing base dependencies..."
sudo apt-get install -y \
    curl wget git unzip jq htop ufw fail2ban python3

# =============================================================================
# STEP 3: Install Node.js 22
# =============================================================================
log "Installing Node.js 22..."
if ! command -v node &>/dev/null || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 22 ]]; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
log "Node.js version: $(node -v)"

# =============================================================================
# STEP 4: Install Go (for building CLIProxyAPIPlus)
# =============================================================================
log "Installing Go..."
if ! command -v go &>/dev/null; then
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ]; then
        GO_ARCH="arm64"
    else
        GO_ARCH="amd64"
    fi
    curl -fsSL "https://go.dev/dl/go1.23.5.linux-${GO_ARCH}.tar.gz" | sudo tar -C /usr/local -xz
fi
export PATH=$PATH:/usr/local/go/bin
log "Go version: $(go version)"

# =============================================================================
# STEP 5: Install Moltbot
# =============================================================================
log "Installing Moltbot..."
if ! command -v clawdbot &>/dev/null && ! command -v moltbot &>/dev/null; then
    curl -fsSL https://molt.bot/install.sh | bash
fi

if command -v clawdbot &>/dev/null; then
    BOT_CMD="clawdbot"
elif command -v moltbot &>/dev/null; then
    BOT_CMD="moltbot"
else
    export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:/usr/local/bin:$PATH"
    if command -v clawdbot &>/dev/null; then
        BOT_CMD="clawdbot"
    elif command -v moltbot &>/dev/null; then
        BOT_CMD="moltbot"
    else
        err "Moltbot binary not found. Check installer output."
        exit 1
    fi
fi
BOT_PATH="$(which $BOT_CMD)"
log "Bot command: $BOT_CMD ($BOT_PATH)"

# =============================================================================
# STEP 6: Build CLIProxyAPIPlus from Source
# =============================================================================
log "Building CLIProxyAPIPlus from source..."
mkdir -p "$HOME/cli-proxy"
if [ ! -d "$PROXY_DIR" ]; then
    git clone --depth 1 https://github.com/router-for-me/CLIProxyAPIPlus.git "$PROXY_DIR"
fi
cd "$PROXY_DIR"
go build -o cli-proxy-api-plus ./cmd/server/
log "CLIProxyAPIPlus built: $(ls -la cli-proxy-api-plus | awk '{print $5}') bytes"

# =============================================================================
# STEP 7: Generate Secure Keys
# =============================================================================
log "Generating secure API key and management secret..."
API_KEY="$(openssl rand -hex 32)"
MGMT_KEY="$(openssl rand -hex 32)"
GATEWAY_TOKEN="$(openssl rand -hex 24)"

# =============================================================================
# STEP 8: Configure CLIProxyAPIPlus
# =============================================================================
log "Writing CLIProxyAPIPlus config..."
cat > "$PROXY_DIR/config.yaml" << CFGEOF
host: "127.0.0.1"
port: 8317

tls:
  enable: false

remote-management:
  allow-remote: false
  secret-key: "${MGMT_KEY}"
  disable-control-panel: false

auth-dir: "~/.cli-proxy-api"

api-keys:
  - "${API_KEY}"

debug: false
logging-to-file: true
logs-max-total-size-mb: 100
request-retry: 3
max-retry-interval: 30
ws-auth: true

routing:
  strategy: "round-robin"

oauth-model-alias:
  claude:
    - name: "claude-sonnet-4-5-20250929"
      alias: "claude-sonnet-4-5"
      fork: true
    - name: "claude-opus-4-5-20251101"
      alias: "claude-opus-4-5"
      fork: true
    - name: "claude-haiku-4-5-20251001"
      alias: "claude-haiku-4-5"
      fork: true
    - name: "claude-sonnet-4-20250514"
      alias: "claude-sonnet-4"
      fork: true
    - name: "claude-opus-4-20250514"
      alias: "claude-opus-4"
      fork: true
    - name: "claude-opus-4-1-20250805"
      alias: "claude-opus-4-1"
      fork: true
    - name: "claude-3-7-sonnet-20250219"
      alias: "claude-3-7-sonnet"
      fork: true
    - name: "claude-3-5-haiku-20241022"
      alias: "claude-3-5-haiku"
      fork: true
CFGEOF

chmod 600 "$PROXY_DIR/config.yaml"

# =============================================================================
# STEP 9: Set Up Moltbot Workspace
# =============================================================================
log "Setting up Moltbot workspace..."
mkdir -p "$WORKSPACE"
mkdir -p "$CONFIG_DIR"

# =============================================================================
# STEP 10: Configure Moltbot to Route Through Proxy
# =============================================================================
log "Configuring Moltbot to use CLIProxyAPIPlus..."

# Store API key securely
sudo mkdir -p /etc/clawdbot
echo "ANTHROPIC_API_KEY=${API_KEY}" | sudo tee /etc/clawdbot/env > /dev/null
echo "ANTHROPIC_BASE_URL=http://127.0.0.1:8317" | sudo tee -a /etc/clawdbot/env > /dev/null
sudo chmod 600 /etc/clawdbot/env

# Set env in Moltbot config
$BOT_CMD config set env.ANTHROPIC_API_KEY "$API_KEY" 2>/dev/null || true
$BOT_CMD config set env.ANTHROPIC_BASE_URL "http://127.0.0.1:8317" 2>/dev/null || true

# Create agent models.json for baseUrl routing
AGENT_DIR="$CONFIG_DIR/agents/main/agent"
mkdir -p "$AGENT_DIR"
cat > "$AGENT_DIR/models.json" << 'MODEOF'
{
  "providers": {
    "anthropic": {
      "baseUrl": "http://127.0.0.1:8317"
    }
  }
}
MODEOF

# =============================================================================
# STEP 11: Create Systemd Services
# =============================================================================
log "Creating systemd services..."

# CLIProxyAPIPlus service (starts first)
sudo tee /etc/systemd/system/cli-proxy-api.service > /dev/null << SVCEOF
[Unit]
Description=CLIProxyAPIPlus Proxy Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=${PROXY_DIR}
ExecStart=${PROXY_DIR}/cli-proxy-api-plus
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

# Moltbot service (starts after proxy)
sudo tee /etc/systemd/system/clawdbot.service > /dev/null << SVCEOF
[Unit]
Description=Moltbot Gateway
After=network-online.target cli-proxy-api.service
Wants=network-online.target cli-proxy-api.service

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=${WORKSPACE}
EnvironmentFile=/etc/clawdbot/env
ExecStart=${BOT_PATH} gateway run --bind loopback --port 18789
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable cli-proxy-api clawdbot

# =============================================================================
# STEP 12: SSH Hardening
# =============================================================================
log "Hardening SSH..."
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null << 'SSHEOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
AllowAgentForwarding no
SSHEOF
sudo systemctl restart sshd

# =============================================================================
# STEP 13: Firewall
# =============================================================================
log "Configuring firewall..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
echo "y" | sudo ufw enable

# =============================================================================
# STEP 14: Fail2ban
# =============================================================================
log "Configuring fail2ban..."
sudo tee /etc/fail2ban/jail.local > /dev/null << 'F2BEOF'
[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 5
bantime = 3600
findtime = 600
F2BEOF
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban

# =============================================================================
# STEP 15: Start CLIProxyAPIPlus
# =============================================================================
log "Starting CLIProxyAPIPlus..."
sudo systemctl start cli-proxy-api
sleep 2

if sudo systemctl is-active --quiet cli-proxy-api; then
    log "CLIProxyAPIPlus is running on 127.0.0.1:8317"
else
    err "CLIProxyAPIPlus failed to start. Check: sudo journalctl -u cli-proxy-api -n 50"
    exit 1
fi

# =============================================================================
# STEP 16: Claude OAuth Authentication
# =============================================================================
echo ""
echo "============================================================================="
echo -e "${GREEN}  CLAUDE OAUTH AUTHENTICATION${NC}"
echo "============================================================================="
echo ""
echo "  You need to authenticate with your Claude Max/Pro account."
echo ""
echo "  The login command will:"
echo "    1. Show an SSH tunnel command — run it on your LOCAL machine"
echo "    2. Show an OAuth URL — open it in your browser"
echo "    3. Sign in with your Claude account"
echo "    4. Credentials are saved locally on this server"
echo ""
echo "  Press Enter to start the Claude OAuth flow..."
read -r

cd "$PROXY_DIR"
./cli-proxy-api-plus --claude-login

# Verify auth
if ls ~/.cli-proxy-api/claude-*.json &>/dev/null; then
    log "Claude OAuth authentication successful!"
    chmod 600 ~/.cli-proxy-api/*.json
    chmod 700 ~/.cli-proxy-api/
else
    warn "No Claude auth files found. You can re-run the login later:"
    warn "  cd $PROXY_DIR && ./cli-proxy-api-plus --claude-login"
fi

# Restart proxy to pick up new auth
sudo systemctl restart cli-proxy-api
sleep 2

# =============================================================================
# STEP 17: Start Moltbot
# =============================================================================
log "Starting Moltbot gateway..."
sudo systemctl start clawdbot
sleep 3

if sudo systemctl is-active --quiet clawdbot; then
    log "Moltbot gateway is running on 127.0.0.1:18789"
else
    warn "Moltbot may not have started. Check: sudo journalctl -u clawdbot -n 50"
fi

# =============================================================================
# SUMMARY
# =============================================================================
MY_IP=$(curl -s ifconfig.me 2>/dev/null || echo "<your-ec2-ip>")

echo ""
echo "============================================================================="
echo -e "${GREEN}  SETUP COMPLETE${NC}"
echo "============================================================================="
echo ""
echo "  Gateway Token:     ${GATEWAY_TOKEN}"
echo "  Proxy API Key:     ${API_KEY}"
echo "  Dashboard Port:    18789"
echo "  Proxy Port:        8317 (localhost only)"
echo ""
echo "  --- SAVE THESE KEYS ---"
echo ""
echo "  Store the Gateway Token and Proxy API Key in a password manager."
echo ""
echo "  --- NEXT STEPS ---"
echo ""
echo "  1. Connect WhatsApp:"
echo "     $BOT_CMD channels login whatsapp"
echo ""
echo "  2. Access the dashboard via SSH tunnel (from your local machine):"
echo "     ssh -L 18789:127.0.0.1:18789 -i <key>.pem ubuntu@${MY_IP}"
echo "     Then open: http://127.0.0.1:18789/"
echo ""
echo "  3. Set your preferred model:"
echo "     $BOT_CMD models set anthropic/claude-sonnet-4-5"
echo ""
echo "  --- USEFUL COMMANDS ---"
echo ""
echo "  $BOT_CMD status              # Bot status"
echo "  $BOT_CMD models list         # Available models"
echo "  $BOT_CMD models set <model>  # Switch model"
echo "  sudo systemctl status clawdbot        # Gateway status"
echo "  sudo systemctl status cli-proxy-api   # Proxy status"
echo "  sudo journalctl -u clawdbot -f        # Gateway logs"
echo "  sudo journalctl -u cli-proxy-api -f   # Proxy logs"
echo ""
echo "  --- RE-AUTHENTICATE CLAUDE ---"
echo ""
echo "  cd $PROXY_DIR && ./cli-proxy-api-plus --claude-login"
echo ""
echo "  --- ROLLBACK TO API KEY ---"
echo ""
echo "  sudo cp /etc/clawdbot/env.backup /etc/clawdbot/env"
echo "  $BOT_CMD config unset env.ANTHROPIC_BASE_URL"
echo "  rm ~/.clawdbot/agents/main/agent/models.json"
echo "  sudo systemctl restart clawdbot"
echo ""
echo "============================================================================="
