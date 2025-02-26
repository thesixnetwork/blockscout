#!/bin/bash

# Create required directories
mkdir -p ./certbot/conf
mkdir -p ./certbot/data

# Make the renewal script executable
chmod +x ssl-renew.sh

# Start initialization
echo "### Starting nginx ..."
docker-compose up -d proxy

# Set up a cron job for certificate renewal
(crontab -l 2>/dev/null; echo "0 12 * * * ~/blockscout/docker-compose/ssl-renew.sh >> /var/log/cron.log 2>&1") | crontab -
echo "### Cron job for certificate renewal has been set up"

echo "### Setup completed! Your site should be accessible via HTTPS shortly."
echo "### Check the certificate status by running: docker logs certbot"