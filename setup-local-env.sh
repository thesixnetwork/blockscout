#!/bin/bash

echo "🚀 Setting up Blockscout Local Development Environment"
echo "======================================================"

# Create backup of current env files
echo "📁 Creating backup of current environment files..."
cp docker-compose/envs/common-blockscout.env docker-compose/envs/common-blockscout.env.backup
cp docker-compose/envs/common-frontend.env docker-compose/envs/common-frontend.env.backup

echo "✅ Backup created!"
echo ""
echo "📝 Next Steps:"
echo "1. Get environment variables from GCP VM:"
echo "   ssh user@your-gcp-vm-ip"
echo "   cat /path/to/production/.env"
echo ""
echo "2. Copy the production values for these key variables:"
echo "   - ETHEREUM_JSONRPC_HTTP_URL"
echo "   - ETHEREUM_JSONRPC_VARIANT" 
echo "   - NEXT_PUBLIC_API_HOST"
echo "   - Network configuration (NEXT_PUBLIC_NETWORK_*)"
echo ""
echo "3. Update your local environment files:"
echo "   - docker-compose/envs/common-blockscout.env"
echo "   - docker-compose/envs/common-frontend.env"
echo ""
echo "4. Restart docker-compose:"
echo "   cd docker-compose"
echo "   docker-compose down"
echo "   docker-compose up"
echo ""
echo "🔧 Environment template files are ready for your production values!"
