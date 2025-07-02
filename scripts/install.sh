#!/bin/bash

# Universal Git Auto-Deployment Agent Installation Script
# For Raspberry Pi (ARM64) and other Linux systems

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/git-deploy-agent"
SERVICE_USER="deploy"
LOG_FILE="/tmp/deploy-agent-install.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Detect system architecture and OS
detect_system() {
    log "Detecting system information..."
    
    ARCH=$(uname -m)
    OS=$(lsb_release -si 2>/dev/null || echo "Unknown")
    VERSION=$(lsb_release -sr 2>/dev/null || echo "Unknown")
    
    log "Architecture: $ARCH"
    log "OS: $OS $VERSION"
    
    # Validate supported architecture
    case $ARCH in
        aarch64|arm64)
            log "ARM64 architecture detected - Compatible with Raspberry Pi 4"
            ;;
        armv7l|armhf)
            log "ARM32 architecture detected - Compatible with Raspberry Pi 3"
            ;;
        x86_64|amd64)
            log "x86_64 architecture detected - Compatible"
            ;;
        *)
            warn "Architecture $ARCH may not be fully tested"
            ;;
    esac
}

# Install system dependencies
install_system_deps() {
    log "Installing system dependencies..."
    
    # Update package list
    apt-get update
    
    # Install required packages
    apt-get install -y \
        curl \
        git \
        build-essential \
        python3 \
        python3-pip \
        nginx \
        systemd \
        sudo \
        wget \
        gnupg \
        lsb-release
    
    log "System dependencies installed successfully"
}

# Install Node.js
install_nodejs() {
    log "Installing Node.js..."
    
    # Check if Node.js is already installed
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version)
        log "Node.js $NODE_VERSION is already installed"
        
        # Check if version is sufficient (>=14)
        MAJOR_VERSION=$(echo $NODE_VERSION | cut -d'.' -f1 | sed 's/v//')
        if [ "$MAJOR_VERSION" -ge 14 ]; then
            log "Node.js version is sufficient"
            return
        else
            warn "Node.js version is too old, installing newer version"
        fi
    fi
    
    # Install Node.js from NodeSource repository
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    
    # Verify installation
    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    log "Node.js $NODE_VERSION and npm $NPM_VERSION installed successfully"
}

# Create service user
create_service_user() {
    log "Creating service user..."
    
    if id "$SERVICE_USER" &>/dev/null; then
        log "User $SERVICE_USER already exists"
    else
        useradd -r -s /bin/bash -d "$INSTALL_DIR" -m "$SERVICE_USER"
        log "Created user $SERVICE_USER"
    fi
    
    # Add user to necessary groups
    usermod -a -G sudo "$SERVICE_USER"
    
    # Allow service user to restart systemd services without password
    echo "$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart *" > "/etc/sudoers.d/$SERVICE_USER"
    echo "$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl start *" >> "/etc/sudoers.d/$SERVICE_USER"
    echo "$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl stop *" >> "/etc/sudoers.d/$SERVICE_USER"
    echo "$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl status *" >> "/etc/sudoers.d/$SERVICE_USER"
    
    log "Service user configured with sudo privileges"
}

# Install application files
install_application() {
    log "Installing application files..."
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    
    # Copy application files
    cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"
    
    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    
    # Install npm dependencies
    cd "$INSTALL_DIR"
    sudo -u "$SERVICE_USER" npm install --production
    
    log "Application files installed successfully"
}

# Create systemd service
create_systemd_service() {
    log "Creating systemd service..."
    
    cat > /etc/systemd/system/git-deploy-agent.service << EOF
[Unit]
Description=Git Auto-Deployment Agent
After=network.target
Wants=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node app.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=3000

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=readonly
ReadWritePaths=$INSTALL_DIR

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=git-deploy-agent

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable git-deploy-agent
    
    log "Systemd service created and enabled"
}

# Configure nginx reverse proxy
configure_nginx() {
    log "Configuring nginx reverse proxy..."
    
    cat > /etc/nginx/sites-available/git-deploy-agent << EOF
server {
    listen 80;
    server_name localhost;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

    # Enable the site
    ln -sf /etc/nginx/sites-available/git-deploy-agent /etc/nginx/sites-enabled/
    
    # Remove default site if it exists
    rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx configuration
    nginx -t
    
    # Reload nginx
    systemctl reload nginx
    
    log "Nginx reverse proxy configured"
}

# Create web interface
create_web_interface() {
    log "Creating web interface..."
    
    mkdir -p "$INSTALL_DIR/public"
    
    cat > "$INSTALL_DIR/public/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Git Deployment Agent</title>
    <style>
        /* ... CSS omitted for brevity ... */
    </style>
</head>
<body>
    <!-- ... HTML omitted for brevity ... -->
</body>
</html>
EOF

    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/public/index.html"
    
    log "Web interface created successfully"
}

# Create setup script
create_setup_script() {
    log "Creating setup script..."
    
    cat > "$INSTALL_DIR/setup.js" << 'EOF'
#!/usr/bin/env node

const fs = require('fs').promises;
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

class SetupWizard {
    constructor() {
        this.configPath = path.join(__dirname, 'config');
        this.settingsPath = path.join(this.configPath, 'settings.json');
    }

    async run() {
        console.log('🚀 Git Deployment Agent Setup Wizard\n');
        
        try {
            await this.setupGitAuthentication();
            await this.configureWebhooks();
            await this.setupFirewall();
            
            console.log('\n✅ Setup completed successfully!');
            console.log('\nNext steps:');
            console.log('1. Start the service: sudo systemctl start git-deploy-agent');
            console.log('2. Check status: sudo systemctl status git-deploy-agent');
            console.log('3. Access web interface: http://localhost');
            console.log('4. Add your first project via the web interface');
            
        } catch (error) {
            console.error('❌ Setup failed:', error.message);
            process.exit(1);
        }
    }

    async setupGitAuthentication() {
        console.log('🔐 Setting up Git authentication...');
        
        // Check if SSH keys exist
        const sshKeyPath = path.join(process.env.HOME, '.ssh', 'id_rsa');
        try {
            await fs.access(sshKeyPath);
            console.log('✅ SSH key found');
        } catch {
            console.log('⚠️  No SSH key found. Generating new SSH key...');
            await execAsync('ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""');
            console.log('✅ SSH key generated');
            
            const publicKey = await fs.readFile(`${sshKeyPath}.pub`, 'utf8');
            console.log('\n📋 Your public SSH key (add this to your Git provider):');
            console.log(publicKey);
            console.log('\nPress Enter after adding the key to your Git provider...');
            await new Promise(resolve => process.stdin.once('data', resolve));
        }
        
        // Test Git access
        try {
            await execAsync('ssh -T git@github.com', { timeout: 10000 });
        } catch (error) {
            if (error.message.includes('successfully authenticated')) {
                console.log('✅ GitHub SSH access verified');
            } else {
                console.log('⚠️  GitHub SSH access test failed (this might be normal)');
            }
        }
    }

    async configureWebhooks() {
        console.log('\n🔗 Webhook configuration...');
        
        await fs.mkdir(this.configPath, { recursive: true });
        
        const settings = {
            pollingInterval: 5,
            webhookSecret: require('crypto').randomBytes(32).toString('hex'),
            maxConcurrentDeployments: 3,
            logRetentionDays: 30
        };
        
        await fs.writeFile(this.settingsPath, JSON.stringify(settings, null, 2));
        
        console.log('✅ Webhook secret generated');
        console.log(`📋 Webhook URL format: http://your-pi-ip/webhook/{project-name}`);
        console.log(`🔑 Webhook secret: ${settings.webhookSecret}`);
    }

    async setupFirewall() {
        console.log('\n🔥 Configuring firewall...');
        
        try {
            // Check if UFW is available
            await execAsync('which ufw');
            
            // Configure UFW rules
            await execAsync('sudo ufw allow 80/tcp');
            await execAsync('sudo ufw allow 3000/tcp');
            
            console.log('✅ Firewall rules configured');
        } catch {
            console.log('⚠️  UFW not found, skipping firewall configuration');
        }
    }
}

// Run setup wizard
if (require.main === module) {
    new SetupWizard().run();
}

module.exports = SetupWizard;
EOF

    chmod +x "$INSTALL_DIR/setup.js"
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/setup.js"
    
    log "Setup script created"
}

# Create migration script
create_migration_script() {
    log "Creating migration script..."
    
    cat > "$INSTALL_DIR/migrate.js" << 'EOF'
#!/usr/bin/env node

const fs = require('fs').promises;
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

class ProjectMigrator {
    constructor() {
        this.configPath = path.join(__dirname, 'config');
        this.projectsPath = path.join(this.configPath, 'projects.json');
    }

    async migrateProject(projectPath) {
        console.log(`🔄 Migrating project from: ${projectPath}`);
        
        try {
            // Resolve absolute path
            const absolutePath = path.resolve(projectPath);
            
            // Check if directory exists
            await fs.access(absolutePath);
            
            // Check if it's a git repository
            const gitPath = path.join(absolutePath, '.git');
            await fs.access(gitPath);
            
            // Get repository information
            process.chdir(absolutePath);
            const { stdout: repoUrl } = await execAsync('git config --get remote.origin.url');
            const { stdout: currentBranch } = await execAsync('git branch --show-current');
            
            // Extract project name from path
            const projectName = path.basename(absolutePath);
            
            // Create project configuration
            const project = {
                name: projectName,
                repoUrl: repoUrl.trim(),
                branch: currentBranch.trim() || 'main',
                deployPath: absolutePath,
                deployScript: 'deploy.sh',
                serviceType: 'systemd',
                serviceName: `${projectName}-service`,
                lastCommit: null,
                lastDeployment: null,
                status: 'ready',
                deploymentHistory: []
            };
            
            // Load existing projects
            let projects = {};
            try {
                const projectsData = await fs.readFile(this.projectsPath, 'utf8');
                projects = JSON.parse(projectsData);
            } catch {
                await fs.mkdir(this.configPath, { recursive: true });
            }
            
            // Add new project
            projects[projectName] = project;
            
            // Save projects configuration
            await fs.writeFile(this.projectsPath, JSON.stringify(projects, null, 2));
            
            // Create deploy script if it doesn't exist
            const deployScriptPath = path.join(absolutePath, 'deploy.sh');
            try {
                await fs.access(deployScriptPath);
                console.log('✅ Deploy script already exists');
            } catch {
                await this.createDeployScript(project);
                console.log('✅ Deploy script created');
            }
            
            console.log(`✅ Project "${projectName}" migrated successfully`);
            console.log(`📋 Repository: ${project.repoUrl}`);
            console.log(`🌿 Branch: ${project.branch}`);
            console.log(`📁 Path: ${project.deployPath}`);
            
        } catch (error) {
            console.error(`❌ Migration failed: ${error.message}`);
            throw error;
        }
    }

    async createDeployScript(project) {
        const deployScriptPath = path.join(project.deployPath, project.deployScript);
        
        // Detect project type
        const packageJsonPath = path.join(project.deployPath, 'package.json');
        const requirementsPath = path.join(project.deployPath, 'requirements.txt');
        const goModPath = path.join(project.deployPath, 'go.mod');
        
        let deployScript = `#!/bin/bash
# Auto-generated deploy script for ${project.name}
set -e

echo "Starting deployment for ${project.name}..."

# Pull latest changes
git pull origin ${project.branch}

`;

        // Add language-specific commands
        try {
            await fs.access(packageJsonPath);
            deployScript += `# Install Node.js dependencies
npm install

# Build if build script exists
if npm run | grep -q "build"; then
    npm run build
fi

`;
        } catch {}

        try {
            await fs.access(requirementsPath);
            deployScript += `# Install Python dependencies
pip3 install -r requirements.txt

`;
        } catch {}

        try {
            await fs.access(goModPath);
            deployScript += `# Download Go dependencies
go mod download

# Build Go application
go build

`;
        } catch {}

        deployScript += `echo "Deployment completed successfully!"
`;

        await fs.writeFile(deployScriptPath, deployScript);
        await execAsync(`chmod +x ${deployScriptPath}`);
    }

    async listProjects() {
        try {
            const projectsData = await fs.readFile(this.projectsPath, 'utf8');
            const projects = JSON.parse(projectsData);
            
            console.log('📋 Configured Projects:');
            console.log('======================');
            
            Object.entries(projects).forEach(([name, project]) => {
                console.log(`\n📦 ${name}`);
                console.log(`   Repository: ${project.repoUrl}`);
                console.log(`   Branch: ${project.branch}`);
                console.log(`   Path: ${project.deployPath}`);
                console.log(`   Status: ${project.status}`);
                console.log(`   Last Deployment: ${project.lastDeployment || 'Never'}`);
            });
            
        } catch (error) {
            console.log('📋 No projects configured yet');
        }
    }
}

// CLI interface
async function main() {
    const migrator = new ProjectMigrator();
    const args = process.argv.slice(2);
    
    if (args.length === 0) {
        console.log('🔄 Project Migration Tool');
        console.log('\nUsage:');
        console.log('  node migrate.js <project-path>  - Migrate existing project');
        console.log('  node migrate.js --list          - List configured projects');
        console.log('\nExamples:');
        console.log('  node migrate.js /home/pi/my-webapp');
        console.log('  node migrate.js ../existing-project');
        process.exit(1);
    }
    
    if (args[0] === '--list') {
        await migrator.listProjects();
    } else {
        await migrator.migrateProject(args[0]);
    }
}

if (require.main === module) {
    main().catch(error => {
        console.error('❌ Error:', error.message);
        process.exit(1);
    });
}

module.exports = ProjectMigrator;
EOF

    chmod +x "$INSTALL_DIR/migrate.js"
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/migrate.js"
    
    log "Migration script created"
}

# Create deploy script templates
create_deploy_templates() {
    log "Creating deploy script templates..."
    
    mkdir -p "$INSTALL_DIR/templates"
    
    # Node.js template
    cat > "$INSTALL_DIR/templates/deploy-nodejs.sh" << 'EOF'
#!/bin/bash
# Node.js deployment script template
set -e

echo "🚀 Starting Node.js deployment..."

# Pull latest changes
git pull origin main

# Install dependencies
npm install --production

# Run tests (optional)
# npm test

# Build project (if applicable)
if npm run | grep -q "build"; then
    echo "📦 Building project..."
    npm run build
fi

# Database migrations (if applicable)
# npm run migrate

echo "✅ Node.js deployment completed successfully!"
EOF

    # Python template
    cat > "$INSTALL_DIR/templates/deploy-python.sh" << 'EOF'
#!/bin/bash
# Python deployment script template
set -e

echo "🐍 Starting Python deployment..."

# Pull latest changes
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

echo "✅ Python deployment completed successfully!"
EOF

    # Go template
    cat > "$INSTALL_DIR/templates/deploy-go.sh" << 'EOF'
#!/bin/bash
# Go deployment script template
set -e

echo "🐹 Starting Go deployment..."

# Pull latest changes
git pull origin main

# Download dependencies
go mod download

# Run tests
go test ./...

# Build application
go build -o app

echo "✅ Go deployment completed successfully!"
EOF

    # Static site template
    cat > "$INSTALL_DIR/templates/deploy-static.sh" << 'EOF'
#!/bin/bash
# Static site deployment script template
set -e

echo "📄 Starting static site deployment..."

# Pull latest changes
git pull origin main

# Install dependencies (if using build tools)
# npm install

# Build site (if applicable)
# npm run build
# hugo
# jekyll build

# Copy files to web directory (example)
# cp -r dist/* /var/www/html/
# cp -r _site/* /var/www/html/

echo "✅ Static site deployment completed successfully!"
EOF

    chmod +x "$INSTALL_DIR/templates/"*.sh
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/templates"
    
    log "Deploy script templates created"
}

# Final setup steps
finalize_installation() {
    log "Finalizing installation..."
    
    # Create log directories
    mkdir -p "$INSTALL_DIR/logs"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/logs"
    
    # Create initial configuration
    mkdir -p "$INSTALL_DIR/config"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/config"
    
    # Set correct permissions
    chmod -R 755 "$INSTALL_DIR"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    
    log "Installation finalized"
}

# Print installation summary
print_summary() {
    log "Installation completed successfully! 🎉"
    echo
    echo "==============================================="
    echo "   Git Auto-Deployment Agent - Installation Summary"
    echo "==============================================="
    echo
    echo "📍 Installation Directory: $INSTALL_DIR"
    echo "👤 Service User: $SERVICE_USER"
    echo "🌐 Web Interface: http://localhost (port 80)"
    echo "🔧 Direct Access: http://localhost:3000"
    echo "📝 Logs: $INSTALL_DIR/logs/"
    echo
    echo "🚀 Getting Started:"
    echo "1. Start the service:"
    echo "   sudo systemctl start git-deploy-agent"
    echo
    echo "2. Enable auto-start on boot:"
    echo "   sudo systemctl enable git-deploy-agent"
    echo
    echo "3. Check service status:"
    echo "   sudo systemctl status git-deploy-agent"
    echo
    echo "4. Run setup wizard:"
    echo "   cd $INSTALL_DIR && sudo -u $SERVICE_USER node setup.js"
    echo
    echo "5. Access web interface:"
    echo "   http://$(hostname -I | awk '{print $1}')"
    echo
    echo "📚 Documentation:"
    echo "- Add projects: Use web interface or migrate.js script"
    echo "- Migrate existing projects: node migrate.js /path/to/project"
    echo "- View logs: journalctl -u git-deploy-agent -f"
    echo "- Configuration: $INSTALL_DIR/config/"
    echo
    echo "🔗 Webhook URL format:"
    echo "   http://your-pi-ip/webhook/{project-name}"
    echo
    echo "==============================================="
}

# Main installation flow
main() {
    log "Starting Git Auto-Deployment Agent installation..."
    
    check_root
    detect_system
    install_system_deps
    install_nodejs
    create_service_user
    install_application
    create_systemd_service
    configure_nginx
    create_web_interface
    create_setup_script
    create_migration_script
    create_deploy_templates
    finalize_installation
    print_summary
    
    log "Installation script completed successfully!"
}

# Run main function
main "$@" 