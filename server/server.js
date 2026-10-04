import express from 'express'
import cors from 'cors'
import http from 'node:http'
import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { Server as SocketIOServer } from 'socket.io'

const app = express()
const httpServer = http.createServer(app)
const io = new SocketIOServer(httpServer, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
  },
})

const PORT = process.env.PORT || 3000
const __dirname = path.dirname(fileURLToPath(import.meta.url))
const DATA_DIR = path.join(__dirname, 'data')
const USERS_FILE = path.join(DATA_DIR, 'users.json')
const MESSAGES_FILE = path.join(DATA_DIR, 'messages.json')

app.use(cors())
app.use(express.json())

const onlineConnections = new Map()

async function readUsers() {
  const data = await fs.readFile(USERS_FILE, 'utf8')
  return JSON.parse(data)
}

async function writeUsers(users) {
  await fs.writeFile(USERS_FILE, JSON.stringify(users, null, 2) + '\n', 'utf8')
}

async function readMessages() {
  try {
    const data = await fs.readFile(MESSAGES_FILE, 'utf8')
    return JSON.parse(data)
  } catch (error) {
    if (error.code === 'ENOENT') {
      await fs.writeFile(MESSAGES_FILE, '[]\n', 'utf8')
      return []
    }
    throw error
  }
}

async function writeMessages(messages) {
  await fs.writeFile(MESSAGES_FILE, JSON.stringify(messages, null, 2) + '\n', 'utf8')
}

function publicUser(user) {
  const { password, ...safeUser } = user
  return safeUser
}

async function setUserStatus(userId, status) {
  const users = await readUsers()
  const user = users.find((item) => item.id === userId)

  if (!user) return null

  user.status = status
  await writeUsers(users)
  return publicUser(user)
}

app.get('/', (_req, res) => {
  res.json({
    message: 'My React Apps chat backend is running',
    status: 'ok',
  })
})

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', service: 'chat-backend' })
})

app.get('/api/users', async (_req, res) => {
  try {
    res.json((await readUsers()).map(publicUser))
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
      password,
      phone: phone?.trim() || '',
      status: 'offline',
    }

    users.push(newUser)
    await writeUsers(users)

    res.status(201).json({
      message: 'Registration successful',
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

    if (!user || user.password !== password) {
      return res.status(401).json({ error: 'Invalid username/email or password' })
    }

    user.status = 'online'
    await writeUsers(users)

    res.json({
      message: 'Login successful',
      user: publicUser(user),
    })
  } catch {
    res.status(500).json({ error: 'Could not log in' })
  }
})

app.post('/api/logout', async (req, res) => {
  try {
    const { userId } = req.body
    const users = await readUsers()
    const user = users.find((item) => item.id === userId)

    if (!user) return res.status(404).json({ error: 'User not found' })

    user.status = 'offline'
    await writeUsers(users)

    res.json({ message: 'Logout successful' })
  } catch {
    res.status(500).json({ error: 'Could not log out' })
  }
})

app.get('/api/messages/:userId/:otherUserId', async (req, res) => {
  try {
    const { userId, otherUserId } = req.params
    const messages = await readMessages()

    const conversation = messages
      .filter(
        (message) =>
          (message.senderId === userId && message.receiverId === otherUserId) ||
          (message.senderId === otherUserId && message.receiverId === userId),
      )
      .sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt))

    res.json(conversation)
  } catch {
    res.status(500).json({ error: 'Could not read message history' })
  }
})

io.on('connection', (socket) => {
  socket.on('user:online', async (userId) => {
    try {
      if (!userId) return

      const users = await readUsers()
      const user = users.find((item) => item.id === userId)
      if (!user) return

      socket.data.userId = userId
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
  })

  socket.on('private:message', async (payload, callback) => {
    try {
      const senderId = socket.data.userId
      const receiverId = payload?.receiverId
      const text = payload?.text?.trim()

      if (!senderId || !receiverId || !text) {
        return callback?.({ ok: false, error: 'Sender, receiver and message text are required' })
      }

      if (text.length > 2000) {
        return callback?.({ ok: false, error: 'Message is too long' })
      }

      const users = await readUsers()
      const receiver = users.find((item) => item.id === receiverId)

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
    const userId = socket.data.userId
    if (!userId) return

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

httpServer.listen(PORT, '0.0.0.0', () => {
  console.log(`Chat backend running on port ${PORT}`)
})
