#!/bin/bash
# Python deployment script template
set -e

echo "🐍 Starting Python deployment..."

git pull origin main
if [ -d "venv" ]; then
    source venv/bin/activate
fi
pip3 install -r requirements.txt
# python manage.py migrate
# python manage.py collectstatic --noinput

echo "✅ Python deployment completed successfully!" 