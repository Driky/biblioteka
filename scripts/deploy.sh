#!/bin/bash
# Deployment script for Webtoon Reader
# Run this script on your server to deploy or update the application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${YELLOW}Webtoon Reader Deployment${NC}"
echo "Project directory: $PROJECT_DIR"
echo ""

# Check for .env file
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please create a .env file based on .env.example"
    exit 1
fi

# Load environment variables
export $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)

# Change to project directory
cd "$PROJECT_DIR"

# Pull latest changes (if using git)
if [ -d ".git" ]; then
    echo -e "${YELLOW}Pulling latest changes...${NC}"
    git pull
fi

# Build and start services
echo -e "${YELLOW}Building and starting services...${NC}"
docker compose build
docker compose up -d

# Wait for postgres to be ready
echo -e "${YELLOW}Waiting for database...${NC}"
sleep 5

# Run migrations
echo -e "${YELLOW}Running database migrations...${NC}"
docker compose exec phoenix /app/bin/webtoon_web eval "WebtoonShared.Release.migrate()"

echo -e "${GREEN}Deployment complete!${NC}"
echo ""
echo "Services status:"
docker compose ps
