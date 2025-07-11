// Universal Git Auto-Deployment Agent for Raspberry Pi
// Main deployment agent (app.js)

const express = require('express');
const fs = require('fs').promises;
const path = require('path');
const crypto = require('crypto');
const { exec, spawn } = require('child_process');
const { promisify } = require('util');
const winston = require('winston');
const cron = require('node-cron');
const bodyParser = require('body-parser');
const os = require('os');

const execAsync = promisify(exec);

class DeploymentAgent {
    constructor() {
        this.app = express();
        this.port = process.env.PORT || 3004;
        this.configPath = path.join(__dirname, '../config');
        this.projectsPath = path.join(this.configPath, 'projects.json');
        this.settingsPath = path.join(this.configPath, 'settings.json');
        this.logsPath = path.join(__dirname, 'logs');
        this.publicPath = path.join(__dirname, '..', 'public');
        this.authPassword = process.env.AGENT_PASSWORD || 'changeme';
        
        this.projects = {};
        this.settings = {};
        this.deploymentQueue = [];
        this.isProcessing = false;
        
        this.setupLogger();
        this.initializeApp();
    }

    setupLogger() {
        // Create logs directory if it doesn't exist
        fs.mkdir(this.logsPath, { recursive: true }).catch(console.error);
        
        this.logger = winston.createLogger({
            level: 'info',
            format: winston.format.combine(
                winston.format.timestamp(),
                winston.format.errors({ stack: true }),
                winston.format.json()
            ),
            defaultMeta: { service: 'deployment-agent' },
            transports: [
                new winston.transports.File({ 
                    filename: path.join(this.logsPath, 'error.log'), 
                    level: 'error' 
                }),
                new winston.transports.File({ 
                    filename: path.join(this.logsPath, 'combined.log') 
                }),
                new winston.transports.Console({
                    format: winston.format.simple()
                })
            ]
        });
    }

    async initializeApp() {
        await this.loadConfiguration();
        // Update password if set in settings
        if (this.settings.AGENT_PASSWORD) {
            this.authPassword = this.settings.AGENT_PASSWORD;
        }
        this.setupMiddleware();
        this.setupRoutes();
        this.startPolling();
        this.startServer();
    }

    async loadConfiguration() {
        try {
            await fs.mkdir(this.configPath, { recursive: true });
            
            // Load projects configuration
            try {
                const projectsData = await fs.readFile(this.projectsPath, 'utf8');
                this.projects = JSON.parse(projectsData);
                // Ensure pollingEnabled is set for all projects
                for (const name in this.projects) {
                    if (typeof this.projects[name].pollingEnabled === 'undefined') {
                        this.projects[name].pollingEnabled = true;
                    }
                }
            } catch (error) {
                this.projects = {};
                await this.saveProjects();
            }

            // Load settings
            try {
                const settingsData = await fs.readFile(this.settingsPath, 'utf8');
                this.settings = JSON.parse(settingsData);
            } catch (error) {
                this.settings = {
                    pollingInterval: 5,
                    webhookSecret: crypto.randomBytes(32).toString('hex'),
                    maxConcurrentDeployments: 3,
                    logRetentionDays: 30
                };
                await this.saveSettings();
            }
        } catch (error) {
            this.logger.error('Failed to load configuration:', error);
        }
    }

    async saveProjects() {
        await fs.writeFile(this.projectsPath, JSON.stringify(this.projects, null, 2));
    }

    async saveSettings() {
        await fs.writeFile(this.settingsPath, JSON.stringify(this.settings, null, 2));
    }

    setupMiddleware() {
        this.app.use(bodyParser.json());
        this.app.use(bodyParser.urlencoded({ extended: true }));
        this.app.use(express.static(this.publicPath));
        // Password protect all /api and sensitive routes
        this.app.use(['/api', '/webhook', '/migrate', '/auth'], this.passwordAuth.bind(this));
        
        // CORS for development
        this.app.use((req, res, next) => {
            res.header('Access-Control-Allow-Origin', '*');
            res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE');
            res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
            next();
        });
    }

    setupRoutes() {
        // Web Interface Routes
        this.app.get('/', (req, res) => {
            res.sendFile(path.join(this.publicPath, 'index.html'));
        });

        // API Routes
        this.app.get('/api/status', (req, res) => {
            res.json({
                status: 'running',
                projects: Object.keys(this.projects).length,
                queueLength: this.deploymentQueue.length,
                isProcessing: this.isProcessing,
                uptime: process.uptime()
            });
        });

        this.app.get('/api/projects', (req, res) => {
            res.json(this.projects);
        });

        this.app.post('/api/projects', async (req, res) => {
            try {
                const { name, repoUrl, branch, deployPath, deployScript, serviceType } = req.body;
                
                if (!name || !repoUrl || !deployPath) {
                    return res.status(400).json({ error: 'Missing required fields' });
                }

                const project = {
                    name,
                    repoUrl,
                    branch: branch || 'main',
                    deployPath: path.resolve(deployPath),
                    deployScript: deployScript || 'deploy.sh',
                    serviceType: serviceType || 'systemd',
                    serviceName: `${name}-service`,
                    lastCommit: null,
                    lastDeployment: null,
                    status: 'inactive',
                    deploymentHistory: [],
                    type: 'custom', // Default to custom
                    pollingEnabled: true // Default to true
                };

                this.projects[name] = project;
                await this.saveProjects();
                
                // Initialize project
                await this.initializeProject(name);
                
                res.json({ success: true, project });
            } catch (error) {
                this.logger.error('Failed to add project:', error);
                res.status(500).json({ error: error.message });
            }
        });

        // --- Deploy Script API ---
        this.app.get('/api/projects/:name/deploy-script', async (req, res) => {
            const { name } = req.params;
            const project = this.projects[name];
            if (!project) return res.status(404).json({ success: false, error: 'Project not found' });
            const deployScriptPath = path.join(project.deployPath, project.deployScript);
            try {
                const content = await fs.readFile(deployScriptPath, 'utf8');
                res.json({ success: true, content });
            } catch (e) {
                res.json({ success: false, error: e.message });
            }
        });
        this.app.post('/api/projects/:name/deploy-script', async (req, res) => {
            const { name } = req.params;
            const { content } = req.body;
            const project = this.projects[name];
            if (!project) return res.status(404).json({ success: false, error: 'Project not found' });
            const deployScriptPath = path.join(project.deployPath, project.deployScript);
            try {
                await fs.writeFile(deployScriptPath, content, 'utf8');
                await execAsync(`chmod +x ${deployScriptPath}`);
                res.json({ success: true });
            } catch (e) {
                res.json({ success: false, error: e.message });
            }
        });
        // --- Stop Project (pm2) ---
        this.app.post('/api/projects/:name/stop', async (req, res) => {
            const { name } = req.params;
            try {
                await execAsync(`pm2 stop ${name}`);
                res.json({ success: true });
            } catch (e) {
                res.json({ success: false, error: e.message });
            }
        });
        // --- Toggle Polling (Auto-Update) ---
        this.app.post('/api/projects/:name/polling', async (req, res) => {
            const { name } = req.params;
            const { enabled } = req.body;
            const project = this.projects[name];
            if (!project) return res.status(404).json({ error: 'Project not found' });
            project.pollingEnabled = !!enabled;
            await this.saveProjects();
            res.json({ success: true, pollingEnabled: project.pollingEnabled });
        });
        // --- Advanced Log Viewing ---
        this.app.get('/api/projects/:name/log', async (req, res) => {
            const { name } = req.params;
            const { search, lines } = req.query;
            const logFile = path.join(this.logsPath, `${name}.log`);
            try {
                let logContent = await fs.readFile(logFile, 'utf8');
                let logLines = logContent.split('\n');
                let n = parseInt(lines) || 200;
                if (search) {
                    logLines = logLines.filter(line => line.toLowerCase().includes(search.toLowerCase()));
                }
                logLines = logLines.slice(-n);
                res.json({ success: true, logs: logLines });
            } catch (e) {
                res.json({ success: false, logs: [], error: e.message });
            }
        });
        this.app.get('/api/projects/:name/log/download', async (req, res) => {
            const { name } = req.params;
            const logFile = path.join(this.logsPath, `${name}.log`);
            try {
                res.download(logFile);
            } catch (e) {
                res.status(404).send('Log not found');
            }
        });
        // --- Delete Project (with folder and log deletion) ---
        this.app.delete('/api/projects/:name', async (req, res) => {
            const { name } = req.params;
            const project = this.projects[name];
            if (!project) return res.status(404).json({ error: 'Project not found' });
            try {
                // Stop pm2 process
                await execAsync(`pm2 stop ${name} || true`);
                await execAsync(`pm2 delete ${name} || true`);
                // Remove project folder
                if (project.deployPath && project.deployPath.length > 8 && project.deployPath !== '/') {
                    await fs.rm(project.deployPath, { recursive: true, force: true });
                }
                // Remove log file
                const logFile = path.join(this.logsPath, `${name}.log`);
                try { await fs.unlink(logFile); } catch {}
                // Remove from config
                delete this.projects[name];
                await this.saveProjects();
                res.json({ success: true });
            } catch (e) {
                res.status(500).json({ error: e.message });
            }
        });

        this.app.post('/api/deploy/:name', async (req, res) => {
            try {
                const { name } = req.params;
                
                if (!this.projects[name]) {
                    return res.status(404).json({ error: 'Project not found' });
                }

                await this.queueDeployment(name, 'manual');
                res.json({ success: true, message: 'Deployment queued' });
            } catch (error) {
                res.status(500).json({ error: error.message });
            }
        });

        // Webhook endpoint
        this.app.post('/webhook/:name', async (req, res) => {
            try {
                const { name } = req.params;
                const signature = req.headers['x-hub-signature-256'];
                
                if (!this.projects[name]) {
                    return res.status(404).json({ error: 'Project not found' });
                }

                // Verify webhook signature if configured
                if (this.settings.webhookSecret && signature) {
                    const hmac = crypto.createHmac('sha256', this.settings.webhookSecret);
                    hmac.update(JSON.stringify(req.body));
                    const digest = 'sha256=' + hmac.digest('hex');
                    
                    if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(digest))) {
                        return res.status(401).json({ error: 'Invalid signature' });
                    }
                }

                // Check if this is a push event to the correct branch
                const project = this.projects[name];
                const payload = req.body;
                
                if (payload.ref === `refs/heads/${project.branch}`) {
                    await this.queueDeployment(name, 'webhook');
                    this.logger.info(`Webhook deployment queued for ${name}`);
                }

                res.json({ success: true });
            } catch (error) {
                this.logger.error('Webhook error:', error);
                res.status(500).json({ error: error.message });
            }
        });

        // Logs endpoint
        this.app.get('/api/logs/:name?', async (req, res) => {
            try {
                const { name } = req.params;
                const download = req.query.download === '1';
                const logFile = name ? 
                    path.join(this.logsPath, `${name}.log`) : 
                    path.join(this.logsPath, 'combined.log');
                if (download) {
                    return res.download(logFile);
                }
                const logs = await fs.readFile(logFile, 'utf8');
                const lines = logs.split('\n').slice(-100); // Last 100 lines
                res.json({ logs: lines });
            } catch (error) {
                res.json({ logs: ['No logs available'] });
            }
        });

        // Serve raw README.md for help tab
        this.app.get('/readme.md', async (req, res) => {
            try {
                const readmePath = path.join(__dirname, '..', 'readme.md');
                const content = await fs.readFile(readmePath, 'utf8');
                res.type('text/markdown').send(content);
            } catch (e) {
                res.status(404).send('# Documentation not found');
            }
        });

        // --- SSH Key Management API ---
        this.app.get('/api/auth/public-key', this.getSshKey.bind(this));
        this.app.post('/api/auth/generate-key', this.generateSshKey.bind(this));
        this.app.post('/api/auth/test-ssh', this.testSsh.bind(this));
        // --- Project Migration API ---
        this.app.post('/api/migrate', this.migrateProject.bind(this));
    }

    async initializeProject(name) {
        const project = this.projects[name];
        
        try {
            // Create deploy directory if it doesn't exist
            await fs.mkdir(project.deployPath, { recursive: true });
            
            // Clone repository if it doesn't exist
            const gitPath = path.join(project.deployPath, '.git');
            try {
                await fs.access(gitPath);
                this.logger.info(`Repository already exists for ${name}`);
            } catch {
                this.logger.info(`Cloning repository for ${name}`);
                await execAsync(`git clone ${project.repoUrl} ${project.deployPath}`);
            }

            // Create deploy.sh from template if type is provided
            const deployScriptPath = path.join(project.deployPath, project.deployScript);
            let templateFile = null;
            if (project.type && project.type !== 'custom') {
                templateFile = path.join(__dirname, '../templates', `deploy-${project.type}.sh`);
                try {
                    await fs.copyFile(templateFile, deployScriptPath);
                    await execAsync(`chmod +x ${deployScriptPath}`);
                    this.logger.info(`Deploy script created from template: deploy-${project.type}.sh`);
                } catch (err) {
                    this.logger.warn(`Could not copy template for type ${project.type}, using default. ${err.message}`);
                    await this.createDefaultDeployScript(project);
                }
            } else {
                try {
                    await fs.access(deployScriptPath);
                } catch {
                    await this.createDefaultDeployScript(project);
                }
            }

            project.status = 'ready';
            await this.saveProjects();
            
        } catch (error) {
            this.logger.error(`Failed to initialize project ${name}:`, error);
            project.status = 'error';
            await this.saveProjects();
        }
    }

    async createDefaultDeployScript(project) {
        const deployScriptPath = path.join(project.deployPath, project.deployScript);
        let defaultScript = `#!/bin/bash\necho "Deploying ${project.name}..."\n`;
        // Add pm2 start/pm2 save for nodejs/python/go
        if (project.type === 'nodejs') {
            defaultScript += `\npm install\npm run build || true\npm run start || pm2 start server.js --name ${project.name}\npm run pm2 save || pm2 save\n`;
        } else if (project.type === 'python') {
            defaultScript += `\npip install -r requirements.txt || true\npython3 main.py || pm2 start main.py --interpreter python3 --name ${project.name}\npm run pm2 save || pm2 save\n`;
        } else if (project.type === 'go') {
            defaultScript += `\ngo mod download || true\ngo build -o app\n./app || pm2 start ./app --name ${project.name}\npm run pm2 save || pm2 save\n`;
        }
        defaultScript += `\necho "Deployment completed successfully!"\n`;
        await fs.writeFile(deployScriptPath, defaultScript);
        await execAsync(`chmod +x ${deployScriptPath}`);
        this.logger.info(`Created default deploy script for ${project.name}`);
    }

    async queueDeployment(projectName, trigger) {
        this.deploymentQueue.push({
            projectName,
            trigger,
            timestamp: new Date().toISOString()
        });

        if (!this.isProcessing) {
            this.processDeploymentQueue();
        }
    }

    async processDeploymentQueue() {
        if (this.isProcessing || this.deploymentQueue.length === 0) {
            return;
        }

        this.isProcessing = true;

        while (this.deploymentQueue.length > 0) {
            const deployment = this.deploymentQueue.shift();
            await this.executeDeployment(deployment);
        }

        this.isProcessing = false;
    }

    async executeDeployment(deployment) {
        const { projectName, trigger, timestamp } = deployment;
        const project = this.projects[projectName];

        if (!project) {
            this.logger.error(`Project ${projectName} not found`);
            return;
        }

        const deploymentId = crypto.randomBytes(8).toString('hex');
        const logFile = path.join(this.logsPath, `${projectName}.log`);

        try {
            this.logger.info(`Starting deployment ${deploymentId} for ${projectName} (${trigger})`);
            
            project.status = 'deploying';
            project.currentDeployment = deploymentId;
            await this.saveProjects();

            // Change to project directory
            process.chdir(project.deployPath);

            // Check for updates
            const { stdout: beforeCommit } = await execAsync('git rev-parse HEAD');
            await execAsync(`git fetch origin ${project.branch}`);
            const { stdout: afterCommit } = await execAsync(`git rev-parse origin/${project.branch}`);

            if (beforeCommit.trim() === afterCommit.trim() && trigger === 'polling') {
                this.logger.info(`No changes detected for ${projectName}`);
                project.status = 'ready';
                delete project.currentDeployment;
                await this.saveProjects();
                return;
            }

            // Execute deployment script
            const deployScriptPath = path.join(project.deployPath, project.deployScript);
            const deployProcess = spawn('bash', [deployScriptPath], {
                cwd: project.deployPath,
                stdio: ['pipe', 'pipe', 'pipe']
            });

            let deployOutput = '';
            deployProcess.stdout.on('data', (data) => {
                deployOutput += data.toString();
            });

            deployProcess.stderr.on('data', (data) => {
                deployOutput += data.toString();
            });

            await new Promise((resolve, reject) => {
                deployProcess.on('close', (code) => {
                    if (code === 0) {
                        resolve();
                    } else {
                        reject(new Error(`Deploy script exited with code ${code}`));
                    }
                });
            });

            // Restart service if configured
            if (project.serviceType === 'systemd' && project.serviceName) {
                try {
                    await execAsync(`sudo systemctl restart ${project.serviceName}`);
                    this.logger.info(`Restarted service ${project.serviceName}`);
                } catch (serviceError) {
                    this.logger.warn(`Failed to restart service ${project.serviceName}:`, serviceError.message);
                }
            }

            // Update project status
            const { stdout: finalCommit } = await execAsync('git rev-parse HEAD');
            project.lastCommit = finalCommit.trim();
            project.lastDeployment = timestamp;
            project.status = 'ready';
            delete project.currentDeployment;
            
            // Add to deployment history
            project.deploymentHistory.unshift({
                id: deploymentId,
                timestamp,
                trigger,
                commit: project.lastCommit,
                success: true,
                output: deployOutput
            });

            // Keep only last 10 deployments
            project.deploymentHistory = project.deploymentHistory.slice(0, 10);

            await this.saveProjects();

            // Log deployment output
            await fs.appendFile(logFile, `\n[${timestamp}] Deployment ${deploymentId} SUCCESS:\n${deployOutput}\n`);
            
            this.logger.info(`Deployment ${deploymentId} completed successfully for ${projectName}`);

        } catch (error) {
            this.logger.error(`Deployment ${deploymentId} failed for ${projectName}:`, error);
            
            project.status = 'error';
            delete project.currentDeployment;
            
            project.deploymentHistory.unshift({
                id: deploymentId,
                timestamp,
                trigger,
                commit: project.lastCommit,
                success: false,
                error: error.message
            });

            project.deploymentHistory = project.deploymentHistory.slice(0, 10);
            await this.saveProjects();

            // Log error
            await fs.appendFile(logFile, `\n[${timestamp}] Deployment ${deploymentId} FAILED: ${error.message}\n`);
        }
    }

    startPolling() {
        const interval = this.settings.pollingInterval || 5;
        
        cron.schedule(`*/${interval} * * * *`, async () => {
            this.logger.debug('Starting polling cycle');
            
            for (const [name, project] of Object.entries(this.projects)) {
                if (project.status === 'ready' && project.pollingEnabled !== false) {
                    await this.queueDeployment(name, 'polling');
                }
            }
        });

        this.logger.info(`Polling started with ${interval} minute interval`);
    }

    startServer() {
        this.app.listen(this.port, () => {
            this.logger.info(`Deployment Agent running on port ${this.port}`);
            console.log(`🚀 Universal Git Auto-Deployment Agent`);
            console.log(`📊 Web Interface: http://localhost:${this.port}`);
            console.log(`🔗 Webhook URL: http://localhost:${this.port}/webhook/{project-name}`);
            console.log(`📝 Logs: ${this.logsPath}`);
        });
    }

    // --- Password Auth Middleware ---
    passwordAuth(req, res, next) {
        const password = req.headers['x-agent-password'] || req.query.password || req.body.password;
        if (password === this.authPassword) {
            return next();
        }
        res.status(401).json({ error: 'Unauthorized: Invalid password' });
    }

    // --- SSH Key Management ---
    async getSshKey(req, res) {
        try {
            const pubKeyPath = path.join(os.homedir(), '.ssh', 'id_rsa.pub');
            console.log('Looking for public key at:', pubKeyPath);
            const pubKey = await fs.readFile(pubKeyPath, 'utf8');
            res.json({ publicKey: pubKey });
        } catch (e) {
            console.error('Failed to read public key:', e);
            res.status(404).json({ error: 'No SSH public key found' });
        }
    }
    async generateSshKey(req, res) {
        const sshDir = path.join(os.homedir(), '.ssh');
        const keyPath = path.join(sshDir, 'id_rsa');
        try {
            await fs.mkdir(sshDir, { recursive: true });
            await execAsync(`ssh-keygen -t rsa -b 4096 -f "${keyPath}" -N ""`);
            res.json({ success: true, message: 'SSH key generated' });
        } catch (e) {
            res.status(500).json({ error: e.message });
        }
    }
    async testSsh(req, res) {
        try {
            const { stdout, stderr } = await execAsync('ssh -T git@github.com', { timeout: 10000 });
            res.json({ success: true, output: stdout + stderr });
        } catch (e) {
            res.json({ success: false, output: e.stdout + e.stderr || e.message });
        }
    }
    // --- Project Migration ---
    async migrateProject(req, res) {
        const { deployPath, name, repo, branch } = req.body;
        if (!deployPath || !name || !repo) {
            return res.status(400).json({ error: 'Missing required fields' });
        }
        try {
            const migrator = require('../scripts/migrate.js');
            await migrator.migrateProject(deployPath, name, repo, branch || 'main');
            // Reload projects.json into memory after migration
            await this.loadConfiguration();
            res.json({ success: true, projects: this.projects });
        } catch (e) {
            // Log migration error to project log and combined log
            const timestamp = new Date().toISOString();
            const logMsg = `\n[${timestamp}] Migration FAILED: ${e.message}\n`;
            this.logger.error(`Migration failed for ${name}:`, e);
            // Log to project log if possible
            if (name && deployPath) {
                const logFile = path.join(this.logsPath, `${name}.log`);
                fs.appendFile(logFile, logMsg).catch(() => {});
            }
            // Also log to combined log
            const combinedLogFile = path.join(this.logsPath, 'combined.log');
            fs.appendFile(combinedLogFile, logMsg).catch(() => {});
            res.status(500).json({ error: e.message });
        }
    }
}

// Error handling
process.on('uncaughtException', (error) => {
    console.error('Uncaught Exception:', error);
    process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

// Start the deployment agent
const agent = new DeploymentAgent();

module.exports = DeploymentAgent; 