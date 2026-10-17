import express from 'express'
import cors from 'cors'
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { randomBytes, scryptSync, timingSafeEqual, createHmac } from 'node:crypto'
import { Server as SocketIOServer } from 'socket.io'
import { MongoClient, GridFSBucket, ObjectId } from 'mongodb'
import multer from 'multer'
import { initializeApp, cert } from 'firebase-admin/app'
import { getMessaging } from 'firebase-admin/messaging'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

// ── Firebase Admin SDK (Cloud Push Notifications when app is closed) ─────────
let firebaseMessaging = null
let firebaseInitStatus = {
  initialized: false,
  source: null,
  error: null,
}

try {
  const possiblePaths = [
    path.join(__dirname, 'firebase-service-account.json'),
    path.resolve('firebase-service-account.json'),
    path.resolve('server/firebase-service-account.json'),
  ]
  const serviceAccountPath = possiblePaths.find((p) => fs.existsSync(p))
  let serviceAccount = null
  let sourceName = null

  if (serviceAccountPath) {
    sourceName = `file:${serviceAccountPath}`
    serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'))
  } else if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    sourceName = 'env:FIREBASE_SERVICE_ACCOUNT'
    let raw = process.env.FIREBASE_SERVICE_ACCOUNT.trim()
    // Support base64 encoded JSON in environment variable
    if (!raw.startsWith('{')) {
      try {
        raw = Buffer.from(raw, 'base64').toString('utf8')
      } catch (_) {}
    }
    serviceAccount = JSON.parse(raw)
  }

  if (serviceAccount) {
    // Critical: Render and cloud env vars store "\n" literally as "\\" and "n".
    // Firebase cert requires real newline characters in private_key.
    if (serviceAccount.private_key && typeof serviceAccount.private_key === 'string') {
      serviceAccount.private_key = serviceAccount.private_key.replace(/\\n/g, '\n')
    }
    const app = initializeApp({
      credential: cert(serviceAccount),
    })
    firebaseMessaging = getMessaging(app)
    firebaseInitStatus = { initialized: true, source: sourceName, error: null }
    console.log(`[Firebase Admin] Initialized successfully from ${sourceName}`)
  } else {
    firebaseInitStatus = { initialized: false, source: 'none', error: 'No credentials configured' }
    console.log('[Firebase Admin] No service account found. Push notifications will be active once configured.')
  }
} catch (e) {
  firebaseInitStatus = { initialized: false, source: 'error', error: e.message }
  console.warn('[Firebase Admin] Initialization failed:', e.message)
}

const app = express()
const httpServer = http.createServer(app)

const FRONTEND_ORIGINS = (process.env.FRONTEND_ORIGIN || '*')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean)

function isAllowedOrigin(origin) {
  return !origin || FRONTEND_ORIGINS.includes('*') || FRONTEND_ORIGINS.includes(origin)
}

const corsOptions = {
  origin: (origin, callback) => {
    if (isAllowedOrigin(origin)) return callback(null, true)
    return callback(new Error('Origin is not allowed by CORS'))
  },
}

const io = new SocketIOServer(httpServer, {
  cors: {
    ...corsOptions,
    methods: ['GET', 'POST'],
  },
  // Aggressive heartbeat for fast disconnect detection (~5s worst case).
  // Proactive /api/me/status calls handle app-background/page-close instantly.
  // These timings are the fallback for true network drops.
  pingInterval: 3000,
  pingTimeout:  2000,
  closeTimeout: 1000,
})

const PORT = process.env.PORT || 3000
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000
const SESSION_SECRET = process.env.SESSION_SECRET || randomBytes(32).toString('hex')
const MONGODB_URI = process.env.MONGODB_URI
const MONGODB_DB_NAME = process.env.MONGODB_DB_NAME || 'chatspace'

if (!MONGODB_URI) {
  console.error('MONGODB_URI is not configured.')
  process.exit(1)
}

if (!process.env.SESSION_SECRET) {
  console.warn('SESSION_SECRET is not set. Sessions will be invalidated when the server restarts.')
}

const mongoClient = new MongoClient(MONGODB_URI)
let db
let usersCollection
let messagesCollection
let mediaBucket

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 50 * 1024 * 1024, // 50MB
  },
  fileFilter: (_req, file, cb) => {
    const ext = (file.originalname || '').toLowerCase()
    const isImageExt = /\.(jpe?g|png|gif|webp|bmp|heic|heif|svg)$/i.test(ext)
    const isVideoExt = /\.(mp4|mov|avi|mkv|webm|3gp|m4v|flv)$/i.test(ext)
    const mimetype = file.mimetype || ''

    if (
      mimetype.startsWith('image/') ||
      mimetype.startsWith('video/') ||
      isImageExt ||
      isVideoExt
    ) {
      cb(null, true)
    } else {
      cb(new Error('Only image and video files are supported.'))
    }
  },
})

app.use(cors(corsOptions))
app.use(express.json())

const onlineConnections = new Map()

function base64Url(value) {
  return Buffer.from(value).toString('base64url')
}

function createToken(userId) {
  const payload = {
    sub: userId,
    exp: Math.floor((Date.now() + SESSION_TTL_MS) / 1000),
  }
  const encoded = base64Url(JSON.stringify(payload))
  const signature = createHmac('sha256', SESSION_SECRET).update(encoded).digest('base64url')
  return encoded + '.' + signature
}

function getSession(token) {
  if (!token) return null

  const [encoded, signature] = token.split('.')
  if (!encoded || !signature) return null

  const expected = createHmac('sha256', SESSION_SECRET).update(encoded).digest('base64url')
  const a = Buffer.from(signature)
  const b = Buffer.from(expected)

  if (a.length !== b.length || !timingSafeEqual(a, b)) return null

  try {
    const payload = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'))
    if (!payload?.sub || !Number.isInteger(payload.exp) || payload.exp <= Math.floor(Date.now() / 1000)) {
      return null
    }
    return { userId: payload.sub, expiresAt: payload.exp * 1000 }
  } catch {
    return null
  }
}

function getBearerToken(req) {
  const header = req.get('authorization')
  if (!header?.startsWith('Bearer ')) return null
  return header.slice(7).trim() || null
}

function authenticateToken(token) {
  return getSession(token)?.userId || null
}

function requireAuth(req, res, next) {
  const token = getBearerToken(req)
  const userId = authenticateToken(token)

  if (!userId) {
    return res.status(401).json({ error: 'Authentication required' })
  }

  req.userId = userId
  next()
}

function hashPassword(password, salt = randomBytes(16).toString('hex')) {
  const hash = scryptSync(password, salt, 64).toString('hex')
  return { salt, hash }
}

function verifyPassword(password, storedPassword, salt) {
  try {
    const derived = scryptSync(password, salt, 64)
    const stored = Buffer.from(storedPassword, 'hex')
    return stored.length === derived.length && timingSafeEqual(stored, derived)
  } catch {
    return false
  }
}

function publicUser(user) {
  const { _id, password, passwordHash, passwordSalt, ...safeUser } = user
  return safeUser
}

function userToPublic(user) {
  if (!user) return null
  return publicUser(user)
}

async function getUserById(userId) {
  return usersCollection.findOne({ id: userId })
}

async function setUserStatus(userId, status, lastSeenAt = null) {
  const update = { $set: { status } }
  if (lastSeenAt) update.$set.lastSeenAt = lastSeenAt
  const result = await usersCollection.findOneAndUpdate(
    { id: userId },
    update,
    { returnDocument: 'after' },
  )
  return userToPublic(result)
}

async function migrateLegacyUsers() {
  const legacyUsers = await usersCollection.find({}).toArray()
  let changed = false

  for (const user of legacyUsers) {
    if (typeof user.password === 'string' && user.password) {
      const passwordData = hashPassword(user.password)
      await usersCollection.updateOne(
        { _id: user._id },
        {
          $set: {
            passwordHash: passwordData.hash,
            passwordSalt: passwordData.salt,
          },
          $unset: { password: '' },
        },
      )
      changed = true
    }
  }

  if (changed) console.log('Migrated plaintext passwords to secure password hashes.')
}

async function authenticateSocket(socket, next) {
  const token = socket.handshake.auth?.token
  const userId = authenticateToken(token)

  if (!userId) {
    return next(new Error('Authentication required'))
  }

  const user = await getUserById(userId)

  if (!user) {
    return next(new Error('User not found'))
  }

  socket.data.userId = userId
  next()
}

io.use((socket, next) => {
  authenticateSocket(socket, next).catch((error) => {
    console.error('Socket authentication error:', error.message)
    next(new Error('Authentication failed'))
  })
})

app.get('/', (_req, res) => {
  res.json({
    message: 'My React Apps chat backend is running',
    status: 'ok',
  })
})

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', service: 'chat-backend' })
})

app.get('/api/me', requireAuth, async (req, res) => {
  try {
    const user = await getUserById(req.userId)

    if (!user) {
      return res.status(401).json({ error: 'Session is no longer valid' })
    }

    res.json({ user: publicUser(user) })
  } catch {
    res.status(500).json({ error: 'Could not load authenticated user' })
  }
})

app.get('/api/users', requireAuth, async (req, res) => {
  try {
    const users = await usersCollection
      .find({ id: { $ne: req.userId } }, { projection: { _id: 0, passwordHash: 0, passwordSalt: 0, password: 0 } })
      .toArray()

    const latestMessages = await messagesCollection.aggregate([
      {
        $match: {
          $or: [
            { senderId: req.userId },
            { receiverId: req.userId },
          ],
        },
      },
      { $sort: { createdAt: -1 } },
      {
        $group: {
          _id: {
            $cond: [
              { $eq: ['$senderId', req.userId] },
              '$receiverId',
              '$senderId',
            ],
          },
          latestMessageAt: { $first: '$createdAt' },
        },
      },
    ]).toArray()

    const latestMessageAt = new Map(
      latestMessages.map((item) => [item._id, item.latestMessageAt]),
    )

    const unreadMessages = await messagesCollection.aggregate([
      {
        $match: {
          receiverId: req.userId,
          readAt: { $exists: false },
        },
      },
      {
        $group: {
          _id: '$senderId',
          unreadCount: { $sum: 1 },
        },
      },
    ]).toArray()

    const unreadCount = new Map(
      unreadMessages.map((item) => [item._id, item.unreadCount]),
    )

    res.json(
      users.map((user) => ({
        ...publicUser(user),
        latestMessageAt: latestMessageAt.get(user.id) || null,
        unreadCount: unreadCount.get(user.id) || 0,
      })),
    )
  } catch (error) {
    console.error('Could not read users:', error.message)
    res.status(500).json({ error: 'Could not read users database' })
  }
})

app.post('/api/register', async (req, res) => {
  try {
    const { name, username, password, phone } = req.body

    if (!name?.trim() || !username?.trim() || !password) {
      return res.status(400).json({ error: 'Name, username/email and password are required' })
    }

    if (password.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' })
    }

    const normalizedUsername = username.trim().toLowerCase()
    const existingUser = await usersCollection.findOne({ username: normalizedUsername })

    if (existingUser) {
      return res.status(409).json({ error: 'An account with this username/email already exists' })
    }

    const newUser = {
      id: 'u' + Date.now(),
      name: name.trim(),
      username: normalizedUsername,
      passwordHash: null,
      passwordSalt: null,
      phone: phone?.trim() || '',
      status: 'offline',
    }

    const passwordData = hashPassword(password)
    newUser.passwordHash = passwordData.hash
    newUser.passwordSalt = passwordData.salt

    await usersCollection.insertOne(newUser)

    const token = createToken(newUser.id)

    res.status(201).json({
      message: 'Registration successful',
      token,
      user: publicUser(newUser),
    })
  } catch {
    res.status(500).json({ error: 'Could not create account' })
  }
})

app.post('/api/login', async (req, res) => {
  try {
    const { username, password } = req.body

    if (!username?.trim() || !password) {
      return res.status(400).json({ error: 'Username/email and password are required' })
    }

    const normalizedUsername = username.trim().toLowerCase()
    const user = await usersCollection.findOne({ username: normalizedUsername })

    const passwordValid = user
      ? user.passwordHash && user.passwordSalt
        ? verifyPassword(password, user.passwordHash, user.passwordSalt)
        : user.password === password
      : false

    if (!user || !passwordValid) {
      return res.status(401).json({ error: 'Invalid username/email or password' })
    }

    if (user.password) {
      const passwordData = hashPassword(password)
      user.passwordHash = passwordData.hash
      user.passwordSalt = passwordData.salt
      delete user.password
      await usersCollection.updateOne(
        { _id: user._id },
        { $set: { passwordHash: user.passwordHash, passwordSalt: user.passwordSalt }, $unset: { password: '' } },
      )
    }

    user.status = 'online'
    await usersCollection.updateOne({ _id: user._id }, { $set: { status: 'online' } })

    const token = createToken(user.id)

    res.json({
      message: 'Login successful',
      token,
      user: publicUser(user),
    })
  } catch {
    res.status(500).json({ error: 'Could not log in' })
  }
})

/**
 * Instant status update endpoint — called proactively by clients before
 * the socket has a chance to disconnect (app background, page close, etc.).
 * This is what makes offline appear instantly instead of waiting for ping timeout.
 */
app.post('/api/me/status', requireAuth, async (req, res) => {
  try {
    const { status } = req.body
    if (status !== 'online' && status !== 'offline') {
      return res.status(400).json({ error: 'Status must be online or offline' })
    }
    const update = { status }
    const lastSeenAt = status === 'offline' ? new Date().toISOString() : null
    if (lastSeenAt) update.lastSeenAt = lastSeenAt
    await usersCollection.updateOne({ id: req.userId }, { $set: update })
    // Broadcast to all connected clients immediately
    io.emit('user:status', { userId: req.userId, status, ...(lastSeenAt && { lastSeenAt }) })
    res.json({ ok: true })
  } catch (error) {
    console.error('Could not update status:', error.message)
    res.status(500).json({ error: 'Could not update status' })
  }
})

/**
 * Public diagnostic endpoint to verify Firebase Admin readiness on server
 */
app.get('/api/push-status', (req, res) => {
  res.json({
    firebaseReady: firebaseInitStatus.initialized,
    source: firebaseInitStatus.source,
    error: firebaseInitStatus.error,
    hasEnvVar: Boolean(process.env.FIREBASE_SERVICE_ACCOUNT),
  })
})

/**
 * Register or update the device's FCM push token for background/closed-app notifications
 */
app.post('/api/me/fcm-token', requireAuth, async (req, res) => {
  try {
    const { token } = req.body
    if (!token || typeof token !== 'string') {
      return res.status(400).json({ error: 'FCM token is required' })
    }
    const result = await usersCollection.updateOne({ id: req.userId }, { $set: { fcmToken: token } })
    console.log(`[FCM] Token registered for user ${req.userId} (matched: ${result.matchedCount}, modified: ${result.modifiedCount})`)
    res.json({ ok: true, matchedCount: result.matchedCount, modifiedCount: result.modifiedCount })
  } catch (error) {
    console.error('Could not save FCM token:', error.message)
    res.status(500).json({ error: 'Could not save FCM token' })
  }
})

app.post('/api/logout', requireAuth, async (req, res) => {
  try {
    const lastSeenAt = new Date().toISOString()
    await usersCollection.updateOne({ id: req.userId }, { $set: { status: 'offline', lastSeenAt } })
    io.emit('user:status', { userId: req.userId, status: 'offline', lastSeenAt })
    res.json({ message: 'Logout successful' })
  } catch (error) {
    console.error('Could not log out:', error.message)
    res.status(500).json({ error: 'Could not log out' })
  }
})

app.post('/api/messages/:userId/:otherUserId/read', requireAuth, async (req, res) => {
  try {
    const { userId, otherUserId } = req.params

    if (req.userId !== userId) {
      return res.status(403).json({ error: 'You can only update your own conversations' })
    }

    await messagesCollection.updateMany(
      {
        senderId: otherUserId,
        receiverId: userId,
        readAt: { $exists: false },
      },
      { $set: { readAt: new Date().toISOString() } },
    )

    res.json({ ok: true })
  } catch (error) {
    console.error('Could not mark messages as read:', error.message)
    res.status(500).json({ error: 'Could not mark messages as read' })
  }
})

app.get('/api/messages/:userId/:otherUserId', requireAuth, async (req, res) => {
  try {
    const { userId, otherUserId } = req.params

    if (req.userId !== userId) {
      return res.status(403).json({ error: 'You can only access your own conversations' })
    }

    const otherUser = await getUserById(otherUserId)
    if (!otherUser) {
      return res.status(404).json({ error: 'Other user not found' })
    }

    const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 40, 1), 100)
    const before = req.query.before
    const filter = {
      $or: [
        { senderId: userId, receiverId: otherUserId },
        { senderId: otherUserId, receiverId: userId },
      ],
    }

    if (before) {
      const beforeDate = new Date(before)
      if (!Number.isNaN(beforeDate.getTime())) {
        filter.createdAt = { $lt: beforeDate.toISOString() }
      }
    }

    if (!before) {
      await messagesCollection.updateMany(
        {
          senderId: otherUserId,
          receiverId: userId,
          readAt: { $exists: false },
        },
        { $set: { readAt: new Date().toISOString() } },
      )
    }

    const conversation = await messagesCollection
      .find(filter)
      .sort({ createdAt: -1 })
      .limit(limit)
      .toArray()

    res.json({
      messages: conversation.reverse(),
      hasMore: conversation.length === limit,
      oldestCreatedAt: conversation[0]?.createdAt || null,
    })
  } catch (error) {
    console.error('Could not read message history:', error.message)
    res.status(500).json({ error: 'Could not read message history' })
  }
})

app.post('/api/upload', requireAuth, (req, res, next) => {
  upload.single('file')(req, res, (err) => {
    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({ error: 'File size exceeds limit of 50MB.' })
      }
      return res.status(400).json({ error: err.message })
    } else if (err) {
      return res.status(400).json({ error: err.message })
    }
    next()
  })
}, async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No media file provided.' })
    }

    if (!mediaBucket) {
      return res.status(500).json({ error: 'Media storage is not ready.' })
    }

    const ext = (req.file.originalname || '').toLowerCase()
    const isVideo = (req.file.mimetype || '').startsWith('video/') || /\.(mp4|mov|avi|mkv|webm|3gp|m4v|flv)$/i.test(ext)
    const mediaType = isVideo ? 'video' : 'image'

    let determinedContentType = req.file.mimetype
    if (!determinedContentType || determinedContentType === 'application/octet-stream') {
      if (isVideo) {
        determinedContentType = ext.endsWith('.mov') ? 'video/quicktime' : 'video/mp4'
      } else {
        determinedContentType = ext.endsWith('.png') ? 'image/png' : 'image/jpeg'
      }
    }

    const uploadStream = mediaBucket.openUploadStream(req.file.originalname, {
      contentType: determinedContentType,
      metadata: {
        uploadedBy: req.userId,
        mediaType,
        size: req.file.size,
        originalName: req.file.originalname,
        createdAt: new Date(),
      },
    })

    uploadStream.on('error', (error) => {
      console.error('GridFS upload error:', error)
      if (!res.headersSent) {
        res.status(500).json({ error: 'Failed to upload media to database.' })
      }
    })

    uploadStream.on('finish', () => {
      const fileId = uploadStream.id.toString()
      res.status(201).json({
        ok: true,
        fileId,
        mediaUrl: `/api/media/${fileId}`,
        mediaType,
        mediaName: req.file.originalname,
        mediaSize: req.file.size,
      })
    })

    uploadStream.end(req.file.buffer)
  } catch (error) {
    console.error('Media upload handler error:', error)
    if (!res.headersSent) {
      res.status(500).json({ error: 'Upload failed: ' + error.message })
    }
  }
})

app.get('/api/media/:fileId', async (req, res) => {
  try {
    const { fileId } = req.params

    if (!fileId || !ObjectId.isValid(fileId)) {
      return res.status(400).json({ error: 'Invalid media ID.' })
    }

    if (!db || !mediaBucket) {
      return res.status(500).json({ error: 'Media storage is not ready.' })
    }

    // Require authentication: Bearer header OR ?token= query parameter
    const token = getBearerToken(req) || (typeof req.query.token === 'string' ? req.query.token.trim() : null)
    const userId = authenticateToken(token)

    if (!userId) {
      return res.status(401).json({ error: 'Authentication required to access private media.' })
    }

    const _id = new ObjectId(fileId)
    const files = await db.collection('media.files').find({ _id }).toArray()

    if (!files || files.length === 0) {
      return res.status(404).json({ error: 'Media not found.' })
    }

    const file = files[0]

    // Authorization: only the uploader or the conversation participants (sender or receiver)
    const isUploader = file.metadata?.uploadedBy === userId
    let isAuthorized = isUploader

    if (!isAuthorized) {
      const message = await messagesCollection.findOne({
        $and: [
          {
            $or: [
              { mediaUrl: `/api/media/${fileId}` },
              { mediaUrl: { $regex: fileId } },
            ],
          },
          {
            $or: [
              { senderId: userId },
              { receiverId: userId },
            ],
          },
        ],
      })
      if (message) {
        isAuthorized = true
      }
    }

    if (!isAuthorized) {
      return res.status(403).json({ error: 'You are not authorized to view this private media.' })
    }

    const fileSize = file.length
    const contentType = file.contentType || 'application/octet-stream'

    res.setHeader('Access-Control-Allow-Origin', '*')
    res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin')
    res.setHeader('Cache-Control', 'private, no-cache, no-store, must-revalidate')
    res.setHeader('Pragma', 'no-cache')
    res.setHeader('Expires', '0')

    const range = req.headers.range
    if (range) {
      const parts = range.replace(/bytes=/, '').split('-')
      const start = parseInt(parts[0], 10)
      const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1

      if (isNaN(start) || start >= fileSize || (parts[1] && isNaN(end)) || end >= fileSize || start > end) {
        res.status(416).set('Content-Range', `bytes */${fileSize}`)
        return res.end()
      }

      const chunkSize = end - start + 1
      res.writeHead(206, {
        'Content-Range': `bytes ${start}-${end}/${fileSize}`,
        'Accept-Ranges': 'bytes',
        'Content-Length': chunkSize,
        'Content-Type': contentType,
        'Cache-Control': 'private, no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      })

      const downloadStream = mediaBucket.openDownloadStream(_id, {
        start,
        end: end + 1,
      })
      downloadStream.on('error', (err) => {
        console.error('Download stream error:', err.message)
        if (!res.headersSent) res.status(500).end()
      })
      downloadStream.pipe(res)
    } else {
      res.writeHead(200, {
        'Content-Length': fileSize,
        'Content-Type': contentType,
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'private, no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      })

      const downloadStream = mediaBucket.openDownloadStream(_id)
      downloadStream.on('error', (err) => {
        console.error('Download stream error:', err.message)
        if (!res.headersSent) res.status(500).end()
      })
      downloadStream.pipe(res)
    }
  } catch (error) {
    console.error('Error serving media from GridFS:', error)
    if (!res.headersSent) {
      res.status(500).json({ error: 'Could not stream media.' })
    }
  }
})

io.on('connection', async (socket) => {
  const userId = socket.data.userId
  socket.join(userId)

  let connections = onlineConnections.get(userId)
  if (!connections) {
    connections = new Set()
    onlineConnections.set(userId, connections)
  }
  connections.add(socket.id)

  try {
    await usersCollection.updateOne({ id: userId }, { $set: { status: 'online' } })
    socket.broadcast.emit('user:status', { userId, status: 'online' })
  } catch (error) {
    console.error('Could not update online status:', error.message)
  }

  socket.on('private:message', async (payload, acknowledge) => {
    const done = typeof acknowledge === 'function' ? acknowledge : () => {}

    try {
      const receiverId = typeof payload?.receiverId === 'string' ? payload.receiverId.trim() : ''
      const messageText = typeof payload?.text === 'string' ? payload.text.trim() : ''
      const mediaUrl = typeof payload?.mediaUrl === 'string' ? payload.mediaUrl.trim() : null
      const mediaType = typeof payload?.mediaType === 'string' ? payload.mediaType.trim() : null
      const mediaName = typeof payload?.mediaName === 'string' ? payload.mediaName.trim() : null
      const mediaSize = typeof payload?.mediaSize === 'number' ? payload.mediaSize : null

      if (!receiverId || (!messageText && !mediaUrl)) {
        return done({ ok: false, error: 'Receiver and message text or media are required' })
      }

      if (messageText.length > 2000) {
        return done({ ok: false, error: 'Message is too long' })
      }

      if (receiverId === userId) {
        return done({ ok: false, error: 'You cannot message yourself' })
      }

      const receiver = await getUserById(receiverId)
      if (!receiver) {
        return done({ ok: false, error: 'Recipient not found' })
      }

      const sender = await getUserById(userId)
      const senderName = sender?.name || sender?.username || 'User'

      const message = {
        id: 'm' + Date.now() + randomBytes(6).toString('hex'),
        senderId: userId,
        senderName,
        receiverId,
        text: messageText,
        mediaUrl,
        mediaType,
        mediaName,
        mediaSize,
        createdAt: new Date().toISOString(),
      }

      await messagesCollection.insertOne(message)

      io.to(userId).emit('private:message', message)
      io.to(receiverId).emit('private:message', message)

      // ── Cloud Push Notification via Firebase (for closed/background mobile app)
      if (firebaseMessaging && receiver?.fcmToken) {
        let preview = messageText
        if (!preview && mediaType) {
          preview = mediaType === 'image' ? '📷 Photo' : mediaType === 'video' ? '🎥 Video' : '📁 Attachment'
        } else if (mediaType === 'image') {
          preview = `📷 ${preview}`
        }

        console.log(`[FCM] Dispatching push notification to ${receiverId} (${senderName}: ${preview})`)
        firebaseMessaging.send({
          token: receiver.fcmToken,
          notification: {
            title: senderName,
            body: preview,
          },
          data: {
            senderId: userId,
            senderName,
            messageId: message.id,
            text: preview,
            type: 'chat_message',
          },
          android: {
            priority: 'high',
            notification: {
              channelId: 'chatspace_messages_channel',
              sound: 'default',
            },
          },
        }).then((response) => {
          console.log(`[FCM] Push delivered successfully to ${receiverId}:`, response)
        }).catch((err) => {
          console.warn('[FCM] Push notification send failed:', err.message)
        })
      } else {
        if (!firebaseMessaging) {
          console.log('[FCM] Skipped push: Firebase Admin is not initialized on server')
        } else if (!receiver?.fcmToken) {
          console.log(`[FCM] Skipped push: Receiver ${receiverId} has no registered fcmToken`)
        }
      }

      done({ ok: true, message })
    } catch (error) {
      console.error('Could not send private message:', error.message)
      done({ ok: false, error: 'Could not send message' })
    }
  })

  socket.on('disconnect', async () => {
    const userConnections = onlineConnections.get(userId)
    if (!userConnections) return

    userConnections.delete(socket.id)

    if (userConnections.size === 0) {
      onlineConnections.delete(userId)

      try {
        const lastSeenAt = new Date().toISOString()
        await usersCollection.updateOne({ id: userId }, { $set: { status: 'offline', lastSeenAt } })
        socket.broadcast.emit('user:status', { userId, status: 'offline', lastSeenAt })
      } catch (error) {
        console.error('Could not update offline status:', error.message)
      }
    }
  })
})

async function startServer() {
  try {
    await mongoClient.connect()
    db = mongoClient.db(MONGODB_DB_NAME)
    usersCollection = db.collection('users')
    messagesCollection = db.collection('messages')
    mediaBucket = new GridFSBucket(db, { bucketName: 'media' })

    await Promise.all([
      usersCollection.createIndex({ id: 1 }, { unique: true }),
      usersCollection.createIndex({ username: 1 }, { unique: true }),
      messagesCollection.createIndex({ senderId: 1, receiverId: 1, createdAt: -1 }),
      messagesCollection.createIndex({ receiverId: 1, senderId: 1, createdAt: -1 }),
    ])

    await migrateLegacyUsers()

    httpServer.listen(PORT, '0.0.0.0', () => {
      console.log(`Chat backend running on port ${PORT}`)
      console.log(`MongoDB database: ${MONGODB_DB_NAME}`)
    })
  } catch (error) {
    console.error('Could not initialize MongoDB:', error)
    process.exit(1)
  }
}

startServer()