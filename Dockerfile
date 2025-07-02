# Universal Git Auto-Deployment Agent Dockerfile
FROM node:20-bullseye

# Install system dependencies (for SSH, git, systemd, etc.)
RUN apt-get update && \
    apt-get install -y openssh-client git sudo && \
    rm -rf /var/lib/apt/lists/*

# Set workdir
WORKDIR /app

# Copy package files and install dependencies
COPY package.json package-lock.json ./
RUN npm install --production

# Copy the rest of the app
COPY . .

# Expose the web port
EXPOSE 3004

# Set environment variables (override with docker-compose or env file)
ENV NODE_ENV=production \
    AGENT_PASSWORD=changeme

# Entrypoint
CMD ["node", "src/agent.js"] 