#!/bin/bash
set -e
if [ $# -lt 2 ]; then
  echo "Usage: $0 <project-name> <git-repo-url> [branch] [deploy-path]"
  exit 1
fi
NAME="$1"
REPO="$2"
BRANCH="${3:-main}"
DEPLOY_PATH="${4:-/opt/$NAME}"
node ../scripts/migrate.js "$DEPLOY_PATH" "$NAME" "$REPO" "$BRANCH" 