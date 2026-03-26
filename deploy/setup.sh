#!/bin/bash
# =============================================================================
# OpenClaw Docker Deployment - Setup Script
# =============================================================================
# Usage: cd deploy && bash setup.sh
# This script initializes the data directory and config files for Docker.
# Run once before the first `docker compose up`.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$SCRIPT_DIR/data"

echo "=== OpenClaw Docker Setup ==="
echo "Deploy dir: $SCRIPT_DIR"
echo "Data dir:   $DATA_DIR"
echo ""

# --- Step 1: Create .env if not exists ---
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  TOKEN=$(openssl rand -hex 32)
  cat > "$SCRIPT_DIR/.env" <<EOF
OPENCLAW_CONFIG_DIR=$DATA_DIR
OPENCLAW_WORKSPACE_DIR=$DATA_DIR/workspace
OPENCLAW_GATEWAY_TOKEN=$TOKEN
OPENCLAW_GATEWAY_BIND=lan

# Uncomment and set if port 18789 is in use:
# OPENCLAW_GATEWAY_PORT=18889
# OPENCLAW_BRIDGE_PORT=18890

# --- LLM API Keys (uncomment and set at least one) ---
# GAUSS_API_KEY=your-company-api-key
# ZAI_API_KEY=your-zai-api-key
# GEMINI_API_KEY=your-gemini-api-key
# OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...
EOF
  echo "[OK] Created .env with token: $TOKEN"
  echo "     SAVE THIS TOKEN - you need it to access Web UI"
else
  echo "[SKIP] .env already exists"
fi

# --- Step 2: Create data directory structure ---
mkdir -p "$DATA_DIR"/{workspace,identity,devices,canvas,agents/main/agent,agents/main/sessions}
echo "[OK] Created data directory structure"

# --- Step 3: Copy config files ---
if [ ! -f "$DATA_DIR/openclaw.json" ]; then
  cp "$SCRIPT_DIR/openclaw.json" "$DATA_DIR/openclaw.json"
  echo "[OK] Copied openclaw.json"
else
  echo "[SKIP] openclaw.json already exists"
fi

if [ ! -f "$DATA_DIR/agents/main/agent/models.json" ]; then
  cp "$SCRIPT_DIR/models.json" "$DATA_DIR/agents/main/agent/models.json"
  echo "[OK] Copied models.json"
else
  echo "[SKIP] models.json already exists"
fi

# --- Step 4: Fix permissions ---
echo "[...] Fixing permissions (requires Docker)..."
docker compose -f "$REPO_DIR/docker-compose.yml" --env-file "$SCRIPT_DIR/.env" \
  run --rm --user root --entrypoint sh openclaw-cli -c \
  'find /home/node/.openclaw -xdev -exec chown node:node {} +' 2>/dev/null || true
# Stop any containers started by the run command
docker compose -f "$REPO_DIR/docker-compose.yml" --env-file "$SCRIPT_DIR/.env" down 2>/dev/null || true
echo "[OK] Permissions fixed"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit deploy/.env - set your LLM API keys"
echo "  2. Start gateway:"
echo "     docker compose --env-file deploy/.env up -d openclaw-gateway"
echo "  3. Open browser: http://localhost:18789"
echo "     (or port you set in OPENCLAW_GATEWAY_PORT)"
echo "  4. Paste your gateway token - no device pairing needed!"
echo ""
