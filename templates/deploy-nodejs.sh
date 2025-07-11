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

echo "🔄 Restarting app with PM2..."
if pm2 list | grep -q "app.js"; then
    pm2 restart app.js --name "$PROJECT_NAME"
else
    pm2 start app.js --name "$PROJECT_NAME"
fi
pm2 save
echo "✅ Node.js deployment completed successfully!" 