# 🚀 Universal Git Auto-Deployment Agent

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Node.js](https://img.shields.io/badge/Node.js-14+-green.svg)](https://nodejs.org/)
[![Docker](https://img.shields.io/badge/Docker-Ready-blue.svg)](https://docker.com/)
[![Platform](https://img.shields.io/badge/Platform-Raspberry%20Pi%20%7C%20Linux-orange.svg)](https://www.raspberrypi.org/)

A universal, production-ready auto-deployment solution for Raspberry Pi and Linux servers. Supports Node.js, Python, Go, static sites, and more. Features multi-project management, webhooks, polling, systemd integration, and a modern web interface.

## ✨ Features

- **🔄 Universal**: Works with any project structure (Node.js, Python, Go, static, etc.)
- **📦 Multi-project**: Manage multiple apps with custom deploy scripts
- **⚡ Triggers**: Webhook (real-time), polling (backup), manual
- **🔧 Service management**: PM2 integration with auto-restart
- **🌐 Web interface**: Modern dashboard with real-time monitoring
- **🔒 Secure**: Webhook signature verification, SSH keys, password-protected API
- **📱 Responsive**: Beautiful, mobile-friendly web interface
- **🐳 Docker Ready**: Full Docker support with persistent data
- **📊 Logs**: Advanced log viewing with search and download
- **🔄 Auto-update**: Per-project polling toggle for automatic updates

## 🚀 Quick Start

### Option 1: Docker (Recommended)
```bash
# Clone the repository
git clone https://github.com/your-username/git-auto-deploy-agent.git
cd git-auto-deploy-agent

# Start with Docker
docker-compose up --build -d

# Access the web interface
open http://localhost:3004
```

### Option 2: Native Installation
```bash
# Clone and setup
git clone https://github.com/your-username/git-auto-deploy-agent.git
cd git-auto-deploy-agent

# Install dependencies
npm install

# Run installation script (Linux/Pi only)
sudo chmod +x scripts/*.sh
sudo ./scripts/install.sh

# Start the agent
npm start
```

## 📋 Prerequisites

- **Node.js 14+** or **Docker**
- **Git** for repository access
- **SSH key** for Git authentication
- **Raspberry Pi** or **Linux server** (for native installation)

## 🛠️ Installation & Setup

### 1. Clone and Enter Directory
```sh
cd git-auto-deploy-agent
```

### 2. Install Node.js Dependencies (Native Only)
```sh
npm install
```

### 3. (Linux/Pi Native) Run the Install Script
```sh
sudo chmod +x scripts/*.sh
sudo ./scripts/install.sh
```
- This script is **only for native (bare metal) installs**. It sets up systemd, nginx, users, and all system-level dependencies.
- **Do NOT run this script inside Docker.**

### 4. Set Up Git Authentication
#### Option 1: Web Interface (Recommended on Linux/Pi)
- Go to the **Authentication** tab in the web UI.
- Use the buttons to:
  - **Generate SSH Key** (creates a new SSH key if not present)
  - **Show Public Key** (copy and add to your GitHub/GitLab account)
  - **Test SSH Connection** (verifies access to your Git provider)

#### Option 2: CLI (Linux/Pi only)
```sh
./scripts/setup-auth.sh
# Add the public key to your GitHub/GitLab account
```

> **Note:** SSH key management features require the agent to run on Linux/Pi with permissions to access `~/.ssh` and run `ssh-keygen`/`ssh`.
> On Windows, use WSL or set up SSH keys manually.

### 5. Start the Agent (for development/testing, native only)
```sh
npm start
# or
node src/agent.js
```

## 🐳 Docker Usage (Recommended for Most Users)

- **You do NOT need to run `install.sh` in Docker.**
- All features (web UI, deployments, webhooks, SSH, password protection, migration, etc.) work fully in Docker.
- Systemd/nginx setup is not needed in Docker; the container runs the agent as a service.

### 1. Build and Start the Container
```sh
docker-compose up --build -d
```

### 2. Access the Web Interface
- Open [http://localhost:3004](http://localhost:3004) (or your server's IP and port 3004) in your browser.

### 3. Stopping the Container
```sh
docker-compose down
```

### 4. Persistent Data
- The following directories are mounted as volumes for persistence:
  - `config/`
  - `logs/`
  - `projects/`
  - `templates/`
  - `public/`
  - Your host's `~/.ssh` is mounted to `/root/.ssh` in the container for Git authentication.

### 5. Change the Agent Password
- Edit the `AGENT_PASSWORD` value in `docker-compose.yaml` or set it as an environment variable.

> **Note:**
> - The agent will run on port **3004** (as set in your Dockerfile and compose file).
> - Make sure port 3004 is open on your firewall if accessing remotely.

## ⚡ Native vs Docker: Which Should I Use?

| Feature                | Native (install.sh) | Docker (Recommended) |
|------------------------|:-------------------:|:-------------------:|
| Web UI                 |         ✔           |         ✔           |
| Deployments            |         ✔           |         ✔           |
| Webhooks               |         ✔           |         ✔           |
| SSH Key Management     |         ✔           |         ✔           |
| Systemd Service        |         ✔           |   (Docker managed)  |
| Nginx Reverse Proxy    |         ✔           |   (Add container)   |
| Password Protection    |         ✔           |         ✔           |
| Logs, Migration, etc.  |         ✔           |         ✔           |

- **Use Docker** for easiest setup, isolation, and portability.
- **Use native install** only if you need systemd/nginx on the host.

## 🌐 Web Interface

- Open [http://localhost:3004](http://localhost:3004) (or your Pi's IP) in your browser.
- **Password required:** Enter the agent password (default: `changeme` or as set in your config/env).

### Dashboard Features:
- **📊 Real-time monitoring** of all projects
- **🔄 Auto-refresh** every 7 seconds
- **📝 Advanced log viewing** with search and download
- **⚙️ Per-project settings** (auto-update toggle)
- **🚀 One-click deployments**
- **🗑️ Project management** (stop, delete, edit)

### Authentication Tab:
- **🔑 SSH key generation** and management
- **🔗 Git provider testing**
- **📋 Public key display** for easy copying

### Migration Tab:
- **📦 Add existing projects** with type selection
- **🎯 Project type templates** (Node.js, Python, Go, Static)
- **📁 Automatic deploy script** generation

## ➕ Adding Projects

### Using the Web Interface
1. Go to the **Migration** tab
2. Fill in project details:
   - **Name**: Your project name
   - **Git Repository**: SSH or HTTPS URL
   - **Deploy Path**: Where to deploy (e.g., `/home/pi/projects/myapp`)
   - **Branch**: Git branch (default: `main`)
   - **Project Type**: Select appropriate template (Node.js, Python, Go, Static, Custom)
3. Click **Migrate Project**
4. Click **Deploy** to start the first deployment

### Using the CLI
```sh
./scripts/add-project.sh myapp git@github.com:user/myapp.git main /opt/myapp
```

## 🔗 Webhook Setup

### GitHub Webhook Configuration:
1. Go to your repository settings
2. Navigate to **Webhooks** → **Add webhook**
3. Set **Payload URL**: `http://<your-pi-ip>:3004/webhook/<project-name>`
4. Set **Content type**: `application/json`
5. Set **Secret**: Use the value from `config/settings.json`
6. Select events: **Just the push event**
7. Click **Add webhook**

### GitLab Webhook Configuration:
1. Go to your project settings
2. Navigate to **Webhooks**
3. Set **URL**: `http://<your-pi-ip>:3004/webhook/<project-name>`
4. Set **Secret Token**: Use the value from `config/settings.json`
5. Select **Push events**
6. Click **Add webhook**

## 📝 Customizing Deploy Scripts

The agent includes templates for different project types:

### Node.js Template (`templates/deploy-nodejs.sh`):
- Installs dependencies with `npm install`
- Runs tests if available
- Builds project if build script exists
- Manages app with PM2
- Auto-restarts after deployment

### Python Template (`templates/deploy-python.sh`):
- Activates virtual environment if present
- Installs dependencies with `pip3 install -r requirements.txt`
- Manages app with PM2 using Python interpreter
- Supports Django migrations and static files

### Go Template (`templates/deploy-go.sh`):
- Downloads dependencies with `go mod download`
- Runs tests with `go test ./...`
- Builds application with `go build -o app`
- Manages app with PM2

### Static Template (`templates/deploy-static.sh`):
- Basic template for static sites
- Can be customized for build tools (Hugo, Jekyll, etc.)

## 🛡️ Security

- **🔐 Password Protection**: All API routes require authentication
- **🔑 SSH Key Management**: Secure Git authentication
- **🔒 Webhook Verification**: Signature verification for all webhooks
- **👤 User Isolation**: Separate user for deployments (native install)
- **📝 Audit Logs**: Complete deployment history and logs

### Security Best Practices:
1. **Change the default password** before exposing to any network
2. **Use SSH keys** instead of passwords for Git access
3. **Keep webhook secrets** secure and unique per project
4. **Regular updates** of the agent and dependencies
5. **Firewall configuration** to limit access to necessary ports

## 🧰 Troubleshooting

### Common Issues:

**Service not starting?**
```bash
# Check systemd logs
journalctl -u git-deploy-agent -f

# Check Docker logs
docker-compose logs -f
```

**Webhook not triggering?**
- Verify webhook URL and secret
- Check agent logs for webhook errors
- Ensure webhook is configured for push events only

**SSH issues?**
```bash
# Test SSH connection
ssh -T git@github.com

# Use web UI to test connection
# Check SSH key permissions
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
```

**Web UI not loading?**
- Verify `public/index.html` exists
- Check file permissions
- Ensure port 3004 is accessible

**PM2 issues?**
```bash
# Check PM2 status
pm2 list

# Restart PM2 daemon
pm2 kill
pm2 start
```

## 📚 Configuration

The application automatically generates configuration files when it first runs:

### Settings (`config/settings.json`):
Generated automatically with default values:
```json
{
  "pollingInterval": 5,
  "webhookSecret": "auto-generated-secret",
  "maxConcurrentDeployments": 3,
  "logRetentionDays": 30
}
```

### Projects (`config/projects.json`):
Generated automatically when projects are added via the web interface or migration script:
```json
{
  "my-project": {
    "name": "my-project",
    "repoUrl": "git@github.com:user/repo.git",
    "branch": "main",
    "deployPath": "/home/pi/projects/my-project",
    "type": "nodejs",
    "pollingEnabled": true,
    "status": "ready",
    "lastCommit": null,
    "lastDeployment": null,
    "deploymentHistory": []
  }
}
```

> **Note:** These files are automatically created and managed by the application. You don't need to create them manually.

## 📁 Project Structure

```
git-auto-deploy-agent/
├── src/
│   ├── agent.js                 # Main deployment agent
│   └── logs/                   # Log files (auto-created)
├── public/
│   ├── index.html              # Web interface
│   └── assets/                 # Static assets (logo, og image)
├── templates/
│   ├── deploy-nodejs.sh        # Node.js template
│   ├── deploy-python.sh        # Python template
│   ├── deploy-go.sh           # Go template
│   └── deploy-static.sh       # Static site template
├── scripts/
│   ├── install.sh             # Installation script
│   ├── migrate.js             # Project migration
│   └── setup-auth.sh         # SSH setup
├── config/                    # Auto-generated config files (root level)
├── projects/                  # Deployed projects (auto-created)
├── docker-compose.yaml       # Docker configuration
├── Dockerfile               # Docker image
├── package.json            # Node.js dependencies
├── LICENSE                 # MIT License
├── CONTRIBUTING.md        # Contributing guidelines
└── README.md             # This documentation
```

> **Note:** The `config/` directory and its files (`settings.json`, `projects.json`) are automatically created when the application first runs. You don't need to create them manually.

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup:
1. Fork the repository
2. Clone your fork
3. Install dependencies: `npm install`
4. Create a feature branch
5. Make your changes
6. Test thoroughly
7. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built for the Raspberry Pi community
- Inspired by the need for simple, reliable deployment solutions
- Thanks to all contributors and users

---

**Made with ❤️ for the Raspberry Pi community**

    


