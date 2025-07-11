#!/usr/bin/env node

const fs = require('fs').promises;
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

class ProjectMigrator {
    constructor() {
        this.configPath = path.join(__dirname, '../config');
        this.projectsPath = path.join(this.configPath, 'projects.json');
    }

    async migrateProject(projectPath, name, repo, branch, type) {
        console.log(`🔄 Migrating project: ${name}`);
        try {
            const absolutePath = path.resolve(projectPath);
            await fs.mkdir(absolutePath, { recursive: true });
            // Clone repo if not present
            try {
                await fs.access(path.join(absolutePath, '.git'));
                console.log('✅ Git repo already exists');
            } catch {
                await execAsync(`git clone -b ${branch} ${repo} ${absolutePath}`);
                console.log('✅ Repo cloned');
            }
            // Create project config
            const project = {
                name,
                repoUrl: repo,
                branch: branch || 'main',
                deployPath: absolutePath,
                deployScript: 'deploy.sh',
                serviceType: 'systemd',
                serviceName: `${name}-service`,
                lastCommit: null,
                lastDeployment: null,
                status: 'ready',
                deploymentHistory: [],
                type: type || 'custom'
            };
            let projects = {};
            try {
                const data = await fs.readFile(this.projectsPath, 'utf8');
                projects = JSON.parse(data);
            } catch {}
            projects[name] = project;
            console.log('Writing to projects.json at:', this.projectsPath);
            try {
                await fs.writeFile(this.projectsPath, JSON.stringify(projects, null, 2));
            } catch (err) {
                console.error('Failed to write projects.json:', err);
                throw err;
            }
            // Create deploy.sh from template if type is provided
            const deployScriptPath = path.join(absolutePath, 'deploy.sh');
            let templateFile = null;
            if (type && type !== 'custom') {
                templateFile = path.join(__dirname, '../templates', `deploy-${type}.sh`);
                try {
                    await fs.copyFile(templateFile, deployScriptPath);
                    await execAsync(`chmod +x ${deployScriptPath}`);
                    console.log(`✅ Deploy script created from template: deploy-${type}.sh`);
                } catch (err) {
                    console.warn(`⚠️ Could not copy template for type ${type}, using minimal default.`, err.message);
                    await fs.writeFile(deployScriptPath, '#!/bin/bash\necho "Deploying ' + name + '..."\n');
                    await execAsync(`chmod +x ${deployScriptPath}`);
                }
            } else {
                try {
                    await fs.access(deployScriptPath);
                    console.log('✅ Deploy script already exists');
                } catch {
                    await fs.writeFile(deployScriptPath, '#!/bin/bash\necho "Deploying ' + name + '..."\n');
                    await execAsync(`chmod +x ${deployScriptPath}`);
                    console.log('✅ Deploy script created');
                }
            }
            console.log(`✅ Project "${name}" migrated successfully`);
        } catch (error) {
            console.error(`❌ Migration failed: ${error.message}`);
            process.exit(1);
        }
    }
}

async function main() {
    const args = process.argv.slice(2);
    if (args.length < 3) {
        console.log('Usage: node migrate.js <deploy-path> <name> <repo> [branch]');
        process.exit(1);
    }
    const [deployPath, name, repo, branch = 'main'] = args;
    const migrator = new ProjectMigrator();
    await migrator.migrateProject(deployPath, name, repo, branch);
}

if (require.main === module) {
    main();
}

module.exports = {
    migrateProject: async (projectPath, name, repo, branch) => {
        const migrator = new ProjectMigrator();
        await migrator.migrateProject(projectPath, name, repo, branch);
    }
}; 