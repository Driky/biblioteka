#!/bin/bash
# SSL Setup Script for Webtoon Reader
# This script obtains SSL certificates from Let's Encrypt

set -e

# Configuration - EDIT THESE
DOMAIN="webtoon.yourdomain.com"
EMAIL="your-email@example.com"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}SSL Certificate Setup for ${DOMAIN}${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    echo -e "${YELLOW}Installing certbot...${NC}"
    apt-get update
    apt-get install -y certbot
fi

# Create webroot directory
echo -e "${YELLOW}Creating webroot directory...${NC}"
mkdir -p /var/www/certbot

# Ensure nginx config allows acme-challenge
echo -e "${YELLOW}Checking nginx configuration...${NC}"

# Get initial certificate
echo -e "${YELLOW}Obtaining SSL certificate...${NC}"
certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN"

# Check if certificate was obtained
if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
    echo -e "${GREEN}Certificate obtained successfully!${NC}"
else
    echo -e "${RED}Failed to obtain certificate${NC}"
    exit 1
fi

# Reload nginx
echo -e "${YELLOW}Reloading nginx...${NC}"
systemctl reload nginx

echo -e "${GREEN}SSL setup complete for ${DOMAIN}${NC}"
echo ""
echo "To set up auto-renewal, run:"
echo "  sudo systemctl enable --now certbot-renewal.timer"
