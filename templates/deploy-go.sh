#!/bin/bash
# Go deployment script template
set -e

echo "🐹 Starting Go deployment..."

# Get project name from current directory or environment
PROJECT_NAME=${PROJECT_NAME:-$(basename $(pwd))}

git pull origin main

# Download dependencies
go mod download

# Run tests
go test ./...

# Build application
go build -o app

echo "🔄 Managing Go app with PM2 (Project: $PROJECT_NAME)..."

# Stop existing process if running
if pm2 list | grep -q "$PROJECT_NAME"; then
    echo "🛑 Stopping existing PM2 process..."
    pm2 stop "$PROJECT_NAME" || true
    pm2 delete "$PROJECT_NAME" || true
fi

# Start the Go app with PM2
echo "▶️ Starting Go app with PM2..."
pm2 start "./app" --name "$PROJECT_NAME"

# Save PM2 configuration
pm2 save

echo "✅ Go deployment completed successfully!"
echo "📊 PM2 Status:"
pm2 list | grep "$PROJECT_NAME" || echo "Process not found in PM2 list" 