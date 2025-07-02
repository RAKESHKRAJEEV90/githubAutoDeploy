# Universal Git Auto-Deployment Agent Dockerfile - Raspberry Pi Optimized
FROM node:20-alpine

# Install system dependencies (lighter Alpine versions)
RUN apk add --no-cache \
    openssh-client \
    git \
    sudo \
    bash

# Create non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -s /bin/bash -u 1000 -G appuser appuser

# Set workdir and change ownership
WORKDIR /app
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Copy package files and install dependencies
COPY --chown=appuser:appuser package.json package-lock.json ./
RUN npm ci --production --no-audit --no-fund

# Copy the rest of the app
COPY --chown=appuser:appuser . .

# Expose the web port
EXPOSE 3004

# Set environment variables
ENV NODE_ENV=production \
    AGENT_PASSWORD=changeme

# Entrypoint
CMD ["node", "src/agent.js"]