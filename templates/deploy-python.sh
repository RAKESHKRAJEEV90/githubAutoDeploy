#!/bin/bash
# Python deployment script template
set -e

echo "🐍 Starting Python deployment..."

# Get project name from current directory or environment
PROJECT_NAME=${PROJECT_NAME:-$(basename $(pwd))}

git pull origin main

# Activate virtual environment (if exists)
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# Install dependencies
pip3 install -r requirements.txt

# Run database migrations (Django example)
# python manage.py migrate

# Collect static files (Django example)
# python manage.py collectstatic --noinput

# Detect main entry file
MAIN_FILE="app.py"
if [ -f "main.py" ]; then
    MAIN_FILE="main.py"
elif [ -f "server.py" ]; then
    MAIN_FILE="server.py"
elif [ -f "run.py" ]; then
    MAIN_FILE="run.py"
fi

echo "🔄 Managing Python app with PM2 (Project: $PROJECT_NAME, Entry: $MAIN_FILE)..."

# Stop existing process if running
if pm2 list | grep -q "$PROJECT_NAME"; then
    echo "🛑 Stopping existing PM2 process..."
    pm2 stop "$PROJECT_NAME" || true
    pm2 delete "$PROJECT_NAME" || true
fi

# Start the Python app with PM2
echo "▶️ Starting Python app with PM2..."
pm2 start "$MAIN_FILE" --name "$PROJECT_NAME" --interpreter python3

# Save PM2 configuration
pm2 save

echo "✅ Python deployment completed successfully!"
echo "📊 PM2 Status:"
pm2 list | grep "$PROJECT_NAME" || echo "Process not found in PM2 list" 