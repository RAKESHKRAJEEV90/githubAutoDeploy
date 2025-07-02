# Universal Git Auto-Deployment Agent for Raspberry Pi

A universal, production-ready auto-deployment solution for Raspberry Pi and Linux servers. Supports Node.js, Python, Go, static sites, and more. Features multi-project management, webhooks, polling, systemd integration, and a modern web interface.

---

## 🚀 Features
- **Universal**: Works with any project structure (Node.js, Python, Go, static, etc.)
- **Multi-project**: Manage multiple apps with custom deploy scripts
- **Triggers**: Webhook (real-time), polling (backup), manual
- **Service management**: systemd integration (native only)
- **Web interface**: Monitor, trigger, and view logs
- **Secure**: Webhook signature verification, SSH keys, password-protected API
- **Easy migration**: Add existing projects with a script or via the web UI

---

## 🛠️ Installation & Setup

### 1. Clone and Enter Directory
```sh
cd 'node js'
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

---

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

---

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

---

## 🌐 Web Interface
- Open [http://localhost:3004](http://localhost:3004) (or your Pi's IP) in your browser.
- **Password required:** Enter the agent password (default: `changeme` or as set in your config/env).
- Use the dashboard to:
  - View system status and logs
  - Add/remove projects
  - Trigger manual deployments
- Use the **Authentication** tab for SSH key management.
- Use the **Migration** tab to migrate existing projects.

---

## ➕ Adding Projects

### Using the Web Interface
- Click **Add Project** and fill in the details (name, repo URL, branch, deploy path, etc.)

### Using the CLI
```sh
./scripts/add-project.sh myapp git@github.com:user/myapp.git main /opt/myapp
```

---

## 🔗 Webhook Setup
- Set your GitHub/GitLab webhook URL to:
  `http://<your-pi-ip>:3004/webhook/<project-name>`
- Use the secret from `config/settings.json` for signature verification.

---

## 📝 Customizing Deploy Scripts
- For each project, copy a template from `templates/` to your project as `deploy.sh` and customize as needed.
- Example: `cp templates/deploy-nodejs.sh /opt/myapp/deploy.sh`

---

## 🛡️ Security
- Webhook secrets are required for all incoming webhooks
- All API and sensitive routes are password-protected (header: `x-agent-password`)
- Only the `deploy` user can run deployments (if using systemd)
- **Change the default password** before exposing the agent to any network!

---

## 🧰 Troubleshooting
- **Service not starting?**
  - Check logs: `journalctl -u git-deploy-agent -f`
- **Webhook not triggering?**
  - Check secret, payload, and logs
- **SSH issues?**
  - Run `ssh -T git@github.com` and check keys
  - Use the **Test SSH Connection** button in the web UI for feedback
- **Web UI not loading?**
  - Ensure `public/index.html` exists and paths are correct in `src/agent.js`
- **SSH Key Management errors?**
  - Make sure you are running the agent on Linux/Pi, not Windows
  - The Node.js process must have permission to access `~/.ssh` and run `ssh-keygen`/`ssh`
  - If you see "No SSH public key found", generate a key first
  - If you see permission errors, check file permissions and user

---

## 📚 Documentation & Help
- All configuration is in `config/`
- Logs are in `logs/`
- Deploy templates are in `templates/`
- Systemd service file is in `systemd/`

---

## 🤝 Contributing
PRs and suggestions welcome!

universal-git-deployer/
├── src/
│   ├── agent.js                 # Main deployment agent
│   ├── webhook-server.js        # Webhook receiver server
│   ├── git-manager.js          # Git operations handler
│   ├── service-manager.js      # SystemD service management
│   ├── project-manager.js      # Project configuration management
│   ├── logger.js               # Logging utility
│   ├── auth-manager.js         # Authentication handling
│   └── web-interface.js        # Web dashboard
├── public/
│   ├── index.html              # Web dashboard UI
│   ├── style.css               # Dashboard styles
│   └── script.js               # Dashboard JavaScript
├── config/
│   ├── projects.json           # Project configurations
│   ├── auth.json               # Authentication credentials
│   └── agent-config.json       # Agent settings
├── templates/
│   ├── deploy-python.sh        # Python deployment template
│   ├── deploy-nodejs.sh        # Node.js deployment template
│   ├── deploy-static.sh        # Static site deployment template
│   ├── deploy-go.sh            # Go deployment template
│   └── systemd-service.template # SystemD service template
├── scripts/
│   ├── install.sh              # Main installation script
│   ├── setup-auth.sh           # Authentication setup
│   ├── add-project.sh          # Add new project script
│   ├── migrate-project.sh      # Migrate existing project
│   └── uninstall.sh            # Uninstall script
├── logs/
│   ├── agent.log               # Main agent logs
│   ├── webhook.log             # Webhook logs
│   └── projects/               # Individual project logs
│       ├── project1.log
│       └── project2.log
├── projects/
│   ├── project1/               # Example project directory
│   │   ├── deploy.sh           # Custom deployment script
│   │   └── .deploy-config      # Project-specific config
│   └── project2/
│       ├── deploy.sh
│       └── .deploy-config
├── package.json                # Node.js dependencies
├── package-lock.json           # Dependency lock file
├── README.md                   # Documentation
├── .env.example                # Environment variables template
├── .gitignore                  # Git ignore file
└── systemd/
    ├── git-deployer.service    # Main agent service
    └── git-webhook.service     # Webhook service

    


