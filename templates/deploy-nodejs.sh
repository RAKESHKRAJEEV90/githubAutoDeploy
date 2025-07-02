#!/bin/bash
# Node.js deployment script template
set -e

echo "🚀 Starting Node.js deployment..."

git pull origin main
npm install --production
# npm test
if npm run | grep -q "build"; then
    npm run build
fi
# npm run migrate

echo "✅ Node.js deployment completed successfully!" 