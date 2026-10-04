import express from 'express'
import cors from 'cors'
import http from 'node:http'
import { randomBytes, scryptSync, timingSafeEqual, createHmac } from 'node:crypto'
import { Server as SocketIOServer } from 'socket.io'
import { MongoClient, ObjectId } from 'mongodb'

const app = express()
const httpServer = http.createServer(app)

const FRONTEND_ORIGIN = process.env.FRONTEND_ORIGIN || '*'
const io = new SocketIOServer(httpServer, {
  cors: {
    origin: FRONTEND_ORIGIN,
    methods: ['GET', 'POST'],
  },
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

app.use(cors({ origin: FRONTEND_ORIGIN }))
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

async function setUserStatus(userId, status) {
  const result = await usersCollection.findOneAndUpdate(
    { id: userId },
    { $set: { status } },
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
    const users = await readUsers()
    const messages = await readMessages()
    const latestMessageAt = new Map()

    for (const message of messages) {
      if (message.senderId !== req.userId && message.receiverId !== req.userId) continue

      const otherUserId = message.senderId === req.userId
        ? message.receiverId
        : message.senderId

      const current = latestMessageAt.get(otherUserId)
      if (!current || new Date(message.createdAt) > new Date(current)) {
        latestMessageAt.set(otherUserId, message.createdAt)
      }
    }

    res.json(
      users
        .filter((user) => user.id !== req.userId)
        .map((user) => ({
          ...publicUser(user),
          latestMessageAt: latestMessageAt.get(user.id) || null,
        }))
    )
  } catch {
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

    const users = await readUsers()
    const normalizedUsername = username.trim().toLowerCase()

    if (users.some((user) => user.username.toLowerCase() === normalizedUsername)) {
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

    users.push(newUser)
    await writeUsers(users)

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

    const users = await readUsers()
    const normalizedUsername = username.trim().toLowerCase()
    const user = users.find((item) => item.username.toLowerCase() === normalizedUsername)

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
      await writeUsers(users)
    }

    user.status = 'online'
    await writeUsers(users)

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

app.post('/api/logout', requireAuth, async (req, res) => {
  try {
    const users = await readUsers()
    const user = users.find((item) => item.id === req.userId)

    if (!user) {
      return res.json({ message: 'Logout successful' })
    }

    user.status = 'offline'
    await writeUsers(users)

    res.json({ message: 'Logout successful' })
  } catch {
    res.status(500).json({ error: 'Could not log out' })
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

    const messages = await readMessages()

    let conversation = messages
      .filter(
        (message) =>
          (message.senderId === userId && message.receiverId === otherUserId) ||
          (message.senderId === otherUserId && message.receiverId === userId),
      )
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))

    if (before) {
      const beforeDate = new Date(before)
      if (!Number.isNaN(beforeDate.getTime())) {
        conversation = conversation.filter((message) => new Date(message.createdAt) < beforeDate)
      }
    }

    const page = conversation.slice(0, limit)
    const oldest = page.at(-1)
    const hasMore = conversation.length > page.length

    res.json({
      messages: page.reverse(),
      hasMore,
      oldestCreatedAt: oldest?.createdAt || null,
    })
  } catch {
    res.status(500).json({ error: 'Could not read message history' })
  }
})

io.on('connection', async (socket) => {
  const userId = socket.data.userId

  try {
    socket.join(userId)

    const count = (onlineConnections.get(userId) || 0) + 1
    onlineConnections.set(userId, count)

    const publicUserData = await setUserStatus(userId, 'online')

    if (publicUserData) {
      io.emit('user:status', { userId, status: 'online' })

      const currentUsers = await readUsers()
      for (const onlineUser of currentUsers) {
        if (onlineUser.id !== userId && onlineUser.status === 'online') {
          socket.emit('user:status', {
            userId: onlineUser.id,
            status: 'online',
          })
        }
      }
    }
  } catch (error) {
    console.error('Could not mark user online:', error.message)
  }

  socket.on('private:message', async (payload, callback) => {
    try {
      const senderId = socket.data.userId
      const receiverId = payload?.receiverId
      const text = payload?.text?.trim()

      if (!senderId || !receiverId || !text) {
        return callback?.({ ok: false, error: 'Receiver and message text are required' })
      }

      if (text.length > 2000) {
        return callback?.({ ok: false, error: 'Message is too long' })
      }

      const receiver = await getUserById(receiverId)

      if (!receiver) {
        return callback?.({ ok: false, error: 'Receiver not found' })
      }

      const messages = await readMessages()
      const message = {
        id: 'm' + Date.now() + Math.random().toString(36).slice(2, 8),
        senderId,
        receiverId,
        text,
        createdAt: new Date().toISOString(),
      }

      messages.push(message)
      await writeMessages(messages)

      io.to(senderId).emit('private:message', message)
      io.to(receiverId).emit('private:message', message)

      callback?.({ ok: true })
    } catch (error) {
      console.error('Could not send message:', error.message)
      callback?.({ ok: false, error: 'Could not send message' })
    }
  })

  socket.on('disconnect', async () => {
    try {
      const count = Math.max((onlineConnections.get(userId) || 1) - 1, 0)

      if (count === 0) {
        onlineConnections.delete(userId)
        const publicUserData = await setUserStatus(userId, 'offline')

        if (publicUserData) {
          io.emit('user:status', { userId, status: 'offline' })
        }
      } else {
        onlineConnections.set(userId, count)
      }
    } catch (error) {
      console.error('Could not mark user offline:', error.message)
    }
  })
})

migratePlaintextPasswords()
  .then(() => {
    httpServer.listen(PORT, '0.0.0.0', () => {
      console.log(`Chat backend running on port ${PORT}`)
    })
  })
  .catch((error) => {
    console.error('Could not initialize user security:', error)
    process.exit(1)
  })
