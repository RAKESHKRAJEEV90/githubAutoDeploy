#!/bin/bash
# Node.js deployment script template
set -e

echo "🚀 Starting Node.js deployment..."

# Get project name from current directory or environment
PROJECT_NAME=${PROJECT_NAME:-$(basename $(pwd))}

git pull origin main
npm install --production

# Run tests if available
if npm run | grep -q "test"; then
    echo "🧪 Running tests..."
    npm test
fi

# Build if build script exists
if npm run | grep -q "build"; then
    echo "📦 Building project..."
    npm run build
fi

# Detect main entry file
MAIN_FILE="app.js"
if [ -f "package.json" ]; then
    # Try to get main from package.json
    MAIN_FROM_PKG=$(node -e "console.log(require('./package.json').main || 'app.js')" 2>/dev/null || echo "app.js")
    if [ -f "$MAIN_FROM_PKG" ]; then
        MAIN_FILE="$MAIN_FROM_PKG"
    fi
fi

echo "🔄 Managing app with PM2 (Project: $PROJECT_NAME, Entry: $MAIN_FILE)..."

# Stop existing process if running
if pm2 list | grep -q "$PROJECT_NAME"; then
    echo "🛑 Stopping existing PM2 process..."
    pm2 stop "$PROJECT_NAME" || true
    pm2 delete "$PROJECT_NAME" || true
fi

# Start the app with PM2
echo "▶️ Starting app with PM2..."
pm2 start "$MAIN_FILE" --name "$PROJECT_NAME"

# Save PM2 configuration
pm2 save

echo "✅ Node.js deployment completed successfully!"
echo "📊 PM2 Status:"
pm2 list | grep "$PROJECT_NAME" || echo "Process not found in PM2 list" 