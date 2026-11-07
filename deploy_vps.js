const { Client } = require('ssh2');
const fs = require('fs');
const path = require('path');

const config = {
  host: '213.199.53.54',
  port: 22,
  username: 'root',
  password: 'VhwC2PtV6Msmyil71KT',
  readyTimeout: 30000
};

const localServerDir = path.join(__dirname, 'server');
const remoteDir = '/root/GALLERY';

const conn = new Client();

console.log('Connecting to VPS for deployment...');

conn.on('ready', () => {
  console.log('Connected! Starting deployment to:', remoteDir);

  conn.sftp((err, sftp) => {
    if (err) throw err;

    // Helper to upload a single file
    function uploadFile(localPath, remotePath) {
      return new Promise((resolve, reject) => {
        sftp.fastPut(localPath, remotePath, (err) => {
          if (err) return reject(err);
          console.log(`Uploaded: ${path.basename(localPath)} -> ${remotePath}`);
          resolve();
        });
      });
    }

    // Helper to run remote command
    function runRemoteCommand(cmd) {
      return new Promise((resolve, reject) => {
        console.log(`Running remote: ${cmd}`);
        conn.exec(cmd, (err, stream) => {
          if (err) return reject(err);
          let stdout = '';
          let stderr = '';
          stream.on('close', (code) => {
            if (code === 0) resolve(stdout);
            else reject(new Error(`Command failed with code ${code}: ${stderr || stdout}`));
          }).on('data', (d) => {
            stdout += d.toString();
            process.stdout.write(d.toString());
          }).stderr.on('data', (d) => {
            stderr += d.toString();
            process.stderr.write(d.toString());
          });
        });
      });
    }

    async function deploy() {
      try {
        // Ensure remote dirs exist
        await runRemoteCommand(`mkdir -p ${remoteDir}/public ${remoteDir}/storage`);

        // Upload files
        await uploadFile(path.join(localServerDir, 'package.json'), `${remoteDir}/package.json`);
        await uploadFile(path.join(localServerDir, 'server.js'), `${remoteDir}/server.js`);
        await uploadFile(path.join(localServerDir, 'public', 'index.html'), `${remoteDir}/public/index.html`);

        // Install packages on VPS
        await runRemoteCommand(`cd ${remoteDir} && npm install --production`);

        // Restart with PM2
        await runRemoteCommand(`pm2 delete gallery-server || true`);
        await runRemoteCommand(`cd ${remoteDir} && pm2 start server.js --name "gallery-server"`);
        await runRemoteCommand(`pm2 save`);
        await runRemoteCommand(`sleep 2 && curl -I http://127.0.0.1:5000/api/health`);

        console.log('\n======================================================');
        console.log('  DEPLOYMENT COMPLETE! SERVER IS LIVE ON VPS!         ');
        console.log('  Web Admin URL: http://213.199.53.54:5000           ');
        console.log('======================================================\n');

        conn.end();
      } catch (e) {
        console.error('Deployment error:', e);
        conn.end();
      }
    }

    deploy();
  });
}).on('error', (err) => {
  console.error('SSH Error:', err);
}).connect(config);
