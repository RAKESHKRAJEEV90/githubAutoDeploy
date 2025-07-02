#!/bin/bash
# Static site deployment script template
set -e

echo "📄 Starting static site deployment..."

git pull origin main
# npm install
# npm run build
# hugo
# jekyll build
# cp -r dist/* /var/www/html/
# cp -r _site/* /var/www/html/

echo "✅ Static site deployment completed successfully!" 