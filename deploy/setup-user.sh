#!/bin/bash
# =============================================================================
# OpenClaw Multi-User Docker Deployment - Setup Script
# =============================================================================
# Usage: bash setup-user.sh [username]
#
# This script creates a separate OpenClaw instance for each user.
# Each user gets their own:
#   - Data directory (users/[username]/data)
#   - Environment file (users/[username]/.env)
#   - Gateway token
#   - Ports (base 18789 + offset)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <username> [options]"
    echo ""
    echo "Arguments:"
    echo "  username    Name for the user instance (required)"
    echo ""
    echo "Options:"
    echo "  --port BASE_PORT   Base port for this instance (default: auto-assign)"
    echo "  --delete           Delete existing user instance"
    echo ""
    echo "Examples:"
    echo "  $0 john                    # Create instance for user 'john'"
    echo "  $0 john --port 18889       # Use custom base port"
    echo "  $0 john --delete           # Delete john's instance"
    exit 1
}

# Parse arguments
if [ $# -lt 1 ]; then
    usage
fi

USERNAME="$1"
shift

# Validate username
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}Error: Username must contain only letters, numbers, underscore, and hyphen${NC}"
    exit 1
fi

USER_DIR="$SCRIPT_DIR/users/$USERNAME"
DATA_DIR="$USER_DIR/data"
ENV_FILE="$USER_DIR/.env"
COMPOSE_FILE="$USER_DIR/docker-compose.yml"

# Default values
BASE_PORT=""
DELETE_MODE=false

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            BASE_PORT="$2"
            shift 2
            ;;
        --delete)
            DELETE_MODE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Delete mode
if [ "$DELETE_MODE" = true ]; then
    if [ -d "$USER_DIR" ]; then
        echo -e "${YELLOW}Deleting instance for user: $USERNAME${NC}"
        read -p "Are you sure? This will delete all data in $USER_DIR (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            # Stop containers first
            if [ -f "$COMPOSE_FILE" ]; then
                echo "Stopping containers..."
                docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
            fi
            rm -rf "$USER_DIR"
            echo -e "${GREEN}Instance deleted successfully${NC}"
        else
            echo "Aborted"
        fi
    else
        echo -e "${YELLOW}No instance found for user: $USERNAME${NC}"
    fi
    exit 0
fi

# Check if instance already exists
if [ -d "$USER_DIR" ]; then
    echo -e "${YELLOW}Instance already exists for user: $USERNAME${NC}"
    echo "Location: $USER_DIR"
    echo ""
    echo "To manage this instance:"
    echo "  cd $USER_DIR"
    echo "  docker compose up -d"
    echo ""
    echo "To delete and recreate:"
    echo "  $0 $USERNAME --delete"
    echo "  $0 $USERNAME"
    exit 0
fi

# Auto-assign port if not specified
if [ -z "$BASE_PORT" ]; then
    # Find existing users and calculate next available port
    BASE_PORT=18789
    if [ -d "$SCRIPT_DIR/users" ]; then
        while IFS= read -r -d '' existing_user_dir; do
            existing_env="$existing_user_dir/.env"
            if [ -f "$existing_env" ]; then
                existing_port=$(grep "^OPENCLAW_GATEWAY_PORT=" "$existing_env" 2>/dev/null | cut -d'=' -f2)
                if [ -n "$existing_port" ] && [ "$existing_port" -ge "$BASE_PORT" ]; then
                    BASE_PORT=$((existing_port + 100))  # Increment by 100 to leave room
                fi
            fi
        done < <(find "$SCRIPT_DIR/users" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi
fi

GATEWAY_PORT=$BASE_PORT
BRIDGE_PORT=$((BASE_PORT + 1))

echo "=== OpenClaw Multi-User Setup ==="
echo "Username:    $USERNAME"
echo "Data Dir:    $DATA_DIR"
echo "Gateway:     http://localhost:$GATEWAY_PORT"
echo ""

# Create user directory structure
mkdir -p "$DATA_DIR"/{workspace,identity,devices,canvas,agents/main/agent,agents/main/sessions}
echo -e "${GREEN}[OK] Created data directory structure${NC}"

# Generate unique token
TOKEN=$(openssl rand -hex 32)

# Create .env file
cat > "$ENV_FILE" <<EOF
# =============================================================================
# OpenClaw Configuration for User: $USERNAME
# =============================================================================
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# =============================================================================

# --- Paths ---
OPENCLAW_CONFIG_DIR=$DATA_DIR
OPENCLAW_WORKSPACE_DIR=$DATA_DIR/workspace

# --- Gateway Settings ---
OPENCLAW_GATEWAY_TOKEN=$TOKEN
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_PORT=$GATEWAY_PORT
OPENCLAW_BRIDGE_PORT=$BRIDGE_PORT

# --- LLM Provider API Keys ---
# Uncomment and set at least one:
# GAUSS_API_KEY=your-company-api-key
# ZAI_API_KEY=your-zai-api-key
# GEMINI_API_KEY=your-gemini-api-key
# OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...
# OPENROUTER_API_KEY=sk-or-...

# --- Optional: Timezone ---
# TZ=Asia/Ho_Chi_Minh
EOF

echo -e "${GREEN}[OK] Created .env with token${NC}"

# Copy config files
if [ ! -f "$DATA_DIR/openclaw.json" ]; then
    cp "$SCRIPT_DIR/openclaw.json" "$DATA_DIR/openclaw.json"
    # Clear wizard state to enable BOOTSTRAP.md behavior
    if command -v jq >/dev/null 2>&1; then
        jq '.wizard = {}' "$DATA_DIR/openclaw.json" > "$DATA_DIR/openclaw.json.tmp" && mv "$DATA_DIR/openclaw.json.tmp" "$DATA_DIR/openclaw.json"
    fi
    echo -e "${GREEN}[OK] Copied openclaw.json (wizard state cleared)${NC}"
fi

if [ ! -f "$DATA_DIR/agents/main/agent/models.json" ]; then
    cp "$SCRIPT_DIR/models.json" "$DATA_DIR/agents/main/agent/models.json"
    echo -e "${GREEN}[OK] Copied models.json${NC}"
fi

# Copy workspace bootstrap templates (for proper AGENTS.md/BOOTSTRAP.md behavior)
WORKSPACE_DIR="$DATA_DIR/workspace"
TEMPLATES_DIR="$REPO_DIR/docs/reference/templates"

# Copy BOOTSTRAP.md - triggers agent "first run" personality setup
if [ -f "$TEMPLATES_DIR/BOOTSTRAP.md" ] && [ ! -f "$WORKSPACE_DIR/BOOTSTRAP.md" ]; then
    cp "$TEMPLATES_DIR/BOOTSTRAP.md" "$WORKSPACE_DIR/BOOTSTRAP.md"
    echo -e "${GREEN}[OK] Copied BOOTSTRAP.md (agent will ask name/personality)${NC}"
fi

# Copy other workspace templates
for template in AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md; do
    if [ -f "$TEMPLATES_DIR/$template" ] && [ ! -f "$WORKSPACE_DIR/$template" ]; then
        cp "$TEMPLATES_DIR/$template" "$WORKSPACE_DIR/$template"
    fi
done

# Note: IDENTITY.md and USER.md will be filled by agent during bootstrapping
# BOOTSTRAP.md will be deleted after agent completes first-time setup

# Copy agent personality templates (optional - already in workspace)
# Note: BOOTSTRAP.md in workspace is the primary location
# Agent-level templates are legacy fallback

# Create user-specific docker-compose.yml
cat > "$COMPOSE_FILE" <<'DOCKERCOMPOSE'
services:
  openclaw-gateway:
    image: ${OPENCLAW_IMAGE:-openclaw:local}
    environment:
      HOME: /root
      TERM: xterm-256color
      OPENCLAW_GATEWAY_TOKEN: ${OPENCLAW_GATEWAY_TOKEN:-}
      # LLM Provider API Keys
      GAUSS_API_KEY: ${GAUSS_API_KEY:-}
      ZAI_API_KEY: ${ZAI_API_KEY:-}
      GEMINI_API_KEY: ${GEMINI_API_KEY:-}
      GOOGLE_API_KEY: ${GOOGLE_API_KEY:-}
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
      OPENROUTER_API_KEY: ${OPENROUTER_API_KEY:-}
      TZ: ${OPENCLAW_TZ:-UTC}
    volumes:
      - ${OPENCLAW_CONFIG_DIR}:/root/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR}:/root/.openclaw/workspace
    extra_hosts:
      - "host.docker.internal:host-gateway"
    ports:
      - "${OPENCLAW_GATEWAY_PORT:-18789}:18789"
      - "${OPENCLAW_BRIDGE_PORT:-18790}:18790"
    init: true
    restart: unless-stopped
    command:
      [
        "node",
        "dist/index.js",
        "gateway",
        "--bind",
        "${OPENCLAW_GATEWAY_BIND:-lan}",
        "--port",
        "18789",
      ]
    healthcheck:
      test:
        [
          "CMD",
          "node",
          "-e",
          "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))",
        ]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 20s
DOCKERCOMPOSE

echo -e "${GREEN}[OK] Created docker-compose.yml${NC}"

# Save connection info
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S" || echo "N/A")

cat > "$USER_DIR/CONNECTION_INFO.txt" <<EOF
=============================================================================
OpenClaw Connection Info - User: $USERNAME
=============================================================================
Generated: $TIMESTAMP

WEB UI:
  URL:    http://localhost:$GATEWAY_PORT
  Token:  $TOKEN

Ports:
  Gateway: $GATEWAY_PORT
  Bridge:  $BRIDGE_PORT

Location:
  Data:    $DATA_DIR
  Config:  $ENV_FILE

Commands:
  # Start services
  cd $USER_DIR && docker compose up -d

  # View logs
  cd $USER_DIR && docker compose logs -f

  # Stop services
  cd $USER_DIR && docker compose down

  # Restart services
  cd $USER_DIR && docker compose restart

API Keys:
  Edit $ENV_FILE and add your API keys

=============================================================================
EOF

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "Connection info saved to: $USER_DIR/CONNECTION_INFO.txt"
echo ""
echo "Quick start:"
echo -e "  ${YELLOW}cd $USER_DIR${NC}"
echo -e "  ${YELLOW}# Edit .env to add your API keys${NC}"
echo -e "  ${YELLOW}docker compose up -d${NC}"
echo ""
echo "Web UI:"
echo -e "  URL:   ${GREEN}http://localhost:$GATEWAY_PORT${NC}"
echo -e "  Token: ${GREEN}$TOKEN${NC}"
echo ""
