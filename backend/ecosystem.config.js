module.exports = {
  apps: [{
    name: "bruh-backend",
    script: "dist/index.js",
    cwd: __dirname,
    node_args: "--experimental-specifier-resolution=node",
    env: {
      NODE_ENV: "production",
      PORT: "3000",
    },
    env_file: ".env",
    max_memory_restart: "512M",
    instances: 1,
    exec_mode: "fork",
    autorestart: true,
    watch: false,
  }],
};
