#!/bin/bash
# Go deployment script template
set -e

echo "🐹 Starting Go deployment..."

git pull origin main
go mod download
go test ./...
go build -o app

echo "✅ Go deployment completed successfully!" 