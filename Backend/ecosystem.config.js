// CODEX EDITS: Versioned PM2 cluster configuration enables wait-ready rolling
// reloads and gives in-flight payment requests time to finish without downtime.
module.exports = {
  apps: [
    {
      name: 'benchbites-api',
      script: './server.js',
      cwd: __dirname,
      instances: 'max',
      exec_mode: 'cluster',
      wait_ready: true,
      listen_timeout: 15000,
      kill_timeout: 30000,
      exp_backoff_restart_delay: 100,
      max_memory_restart: '500M',
      merge_logs: true,
      time: true,
      env: {
        NODE_ENV: 'production',
      },
    },
  ],
};
