module.exports = {
  apps: [{
    name: 'bruh-backend',
    script: 'node_modules/.bin/tsx',
    args: 'src/index.ts',
    cwd: '/opt/bruh-backend',
    env_file: '.env',
    max_memory_restart: '512M',
    instances: 1,
    exec_mode: 'fork',
    autorestart: true,
    watch: false,
  }],
};
