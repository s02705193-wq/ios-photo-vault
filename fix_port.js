const { Client } = require('ssh2');

const c = new Client();
c.on('ready', () => {
  const cmd = `
    fuser -k 5000/tcp || true
    pm2 delete gallery-server || true
    cd /root/GALLERY
    pm2 start server.js --name "gallery-server"
    pm2 save
    sleep 2
    pm2 list
    curl -I http://127.0.0.1:5000/api/health
  `;
  c.exec(cmd, (err, stream) => {
    stream.on('data', d => process.stdout.write(d.toString()));
    stream.on('close', () => c.end());
  });
}).connect({
  host: '213.199.53.54',
  port: 22,
  username: 'root',
  password: 'VhwC2PtV6Msmyil71KT'
});
