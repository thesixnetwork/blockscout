#!/bin/bash
export DOCKER="/usr/bin/docker"
export COMPOSE="/usr/bin/docker compose"

cd ~/blockscout/docker-compose/

# Check if certificates need renewal
$DOCKER run --rm --name certbot-renewal-check \
  --volume $PWD/certbot/conf:/etc/letsencrypt \
  --volume $PWD/certbot/data:/var/www/certbot \
  certbot/certbot:latest renew --dry-run

# If certificates need renewal, initiate the renewal process
$DOCKER run --rm --name certbot-renewal \
  --volume $PWD/certbot/conf:/etc/letsencrypt \
  --volume $PWD/certbot/data:/var/www/certbot \
  certbot/certbot:latest renew

# Restart Nginx to apply new certificates if renewed
$DOCKER exec proxy nginx -s reload