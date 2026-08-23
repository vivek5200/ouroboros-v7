#!/usr/bin/env bash
# =============================================================================
# Ouroboros v7.1 — One-Click Launch Script
# =============================================================================
#
# Validates environment, builds the Docker image, and starts the container
# with NVIDIA GPU passthrough.
#
# Prerequisites:
#   - OX_ALPHA_API_KEY and OX_ALPHA_BASE_URL environment variables set
#     (OpenAI-compatible ox-alpha API endpoint)
#   - Docker installed with nvidia-container-toolkit
#   - NVIDIA GPU with CUDA 12.6 support
#
# Usage:
#   chmod +x launch.sh
#   ./launch.sh
#   (credentials are read from the environment or a local .env file)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Color codes for output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Load local secrets (.env) if present
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/.env" ]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/.env"
    echo -e "${YELLOW}[ouroboros] Loaded configuration from .env${NC}"
fi

# ---------------------------------------------------------------------------
# Validate environment
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[ouroboros] Validating environment...${NC}"

if [ -z "${OX_ALPHA_API_KEY:-}" ]; then
    echo -e "${RED}[ERROR] OX_ALPHA_API_KEY is not set.${NC}"
    echo "  Export it before running this script:"
    echo "    export OX_ALPHA_API_KEY=\"your-ox-alpha-api-key\""
    exit 1
fi

if [ -z "${OX_ALPHA_BASE_URL:-}" ]; then
    echo -e "${RED}[ERROR] OX_ALPHA_BASE_URL is not set.${NC}"
    echo "  Export the OpenAI-compatible base URL of the ox-alpha API:"
    echo "    export OX_ALPHA_BASE_URL=\"https://api.example.com/v1\""
    echo "  (If the endpoint runs on this host, use a URL reachable from the"
    echo "   container, e.g. http://host.docker.internal:PORT/v1.)"
    exit 1
fi

echo -e "${GREEN}[ouroboros] API configuration validated (model: ${OX_ALPHA_MODEL:-ox-alpha}).${NC}"

# ---------------------------------------------------------------------------
# Navigate to script directory (ensures relative paths work)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo -e "${YELLOW}[ouroboros] Working directory: ${SCRIPT_DIR}${NC}"

# ---------------------------------------------------------------------------
# Build Docker image
# ---------------------------------------------------------------------------
IMAGE_NAME="ouroboros-unified"
CONTAINER_NAME="ouroboros-runtime"

echo -e "${YELLOW}[ouroboros] Building Docker image '${IMAGE_NAME}'...${NC}"
docker build \
    -t "${IMAGE_NAME}" \
    -f docker/unified-ci.Dockerfile \
    ..

echo -e "${GREEN}[ouroboros] Docker image built successfully.${NC}"

# ---------------------------------------------------------------------------
# Stop existing container if running
# ---------------------------------------------------------------------------
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${YELLOW}[ouroboros] Stopping existing container '${CONTAINER_NAME}'...${NC}"
    docker rm -f "${CONTAINER_NAME}" > /dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# Start container with GPU passthrough
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[ouroboros] Starting container '${CONTAINER_NAME}' with GPU passthrough...${NC}"
docker run -d \
    --gpus all \
    --name "${CONTAINER_NAME}" \
    -e OX_ALPHA_API_KEY="${OX_ALPHA_API_KEY}" \
    -e OX_ALPHA_BASE_URL="${OX_ALPHA_BASE_URL}" \
    -e OX_ALPHA_MODEL="${OX_ALPHA_MODEL:-ox-alpha}" \
    -e ECC_BUDGET="${ECC_BUDGET:-0.00}" \
    -v "${SCRIPT_DIR}":/workspace/ouroboros-v7 \
    "${IMAGE_NAME}"

echo -e "${GREEN}[ouroboros] Container '${CONTAINER_NAME}' started successfully.${NC}"
echo ""
echo -e "${GREEN}=== Ouroboros v7.1 Runtime Active ===${NC}"
echo ""
echo "  Monitor logs:   docker logs -f ${CONTAINER_NAME}"
echo "  Shell access:   docker exec -it ${CONTAINER_NAME} bash"
echo "  Stop:           docker stop ${CONTAINER_NAME}"
echo ""
