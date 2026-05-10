#!/bin/bash
# =============================================================================
# OpenClaw Multi-User Deployment - Server Setup (One-Time)
# =============================================================================
# Usage: bash setup-server.sh
#
# Builds the prerequisite Docker images for multi-user sandbox deployment.
# Run this ONCE per server before creating any user instances.
#
# Images built:
#   - openclaw:local              (gateway with Docker CLI inside)
#   - openclaw-sandbox:bookworm-slim  (sandbox base image)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=== OpenClaw Server Setup ==="
echo "Repo: $REPO_DIR"
echo ""

# Check Docker is available
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

# Check repo structure exists
if [ ! -f "$REPO_DIR/Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile not found at $REPO_DIR/Dockerfile${NC}"
    echo "Please run this script from the deploy/ directory inside the repo."
    exit 1
fi

if [ ! -f "$REPO_DIR/scripts/docker/sandbox/Dockerfile" ]; then
    echo -e "${RED}Error: Sandbox Dockerfile not found at $REPO_DIR/scripts/docker/sandbox/Dockerfile${NC}"
    exit 1
fi

# Build gateway image with Docker CLI
echo -e "${CYAN}[1/2] Building gateway image (openclaw:local) with Docker CLI...${NC}"
echo "    This takes 2-5 minutes depending on network and machine."
echo ""

cd "$REPO_DIR"
docker build \
    -t openclaw:local \
    --build-arg OPENCLAW_INSTALL_DOCKER_CLI=1 \
    .

echo -e "${GREEN}[OK] Gateway image built: openclaw:local${NC}"
echo ""

# Build sandbox base image
echo -e "${CYAN}[2/2] Building sandbox base image (openclaw-sandbox:bookworm-slim)...${NC}"
echo "    This takes 1-3 minutes."
echo ""

docker build \
    -t openclaw-sandbox:bookworm-slim \
    -f scripts/docker/sandbox/Dockerfile \
    .

echo -e "${GREEN}[OK] Sandbox image built: openclaw-sandbox:bookworm-slim${NC}"
echo ""

# Verify
echo -e "${CYAN}Verifying images...${NC}"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E 'REPOSITORY|openclaw'
echo ""

echo -e "${GREEN}=== Server Setup Complete ===${NC}"
echo ""
echo "You can now create user instances:"
echo -e "  ${YELLOW}cd deploy${NC}"
echo -e "  ${YELLOW}bash setup-user.sh john --sandbox${NC}"
echo ""
