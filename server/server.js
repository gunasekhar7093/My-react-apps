import express from 'express'
import cors from 'cors'
import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const app = express()
const PORT = process.env.PORT || 3000
const __dirname = path.dirname(fileURLToPath(import.meta.url))
const DATA_FILE = path.join(__dirname, 'data', 'users.json')

app.use(cors())
app.use(express.json())

async function readUsers() {
  const data = await fs.readFile(DATA_FILE, 'utf8')
  return JSON.parse(data)
}

async function writeUsers(users) {
  await fs.writeFile(DATA_FILE, JSON.stringify(users, null, 2) + '\n', 'utf8')
}

function publicUser(user) {
  const { password, ...safeUser } = user
  return safeUser
}

app.get('/', (_req, res) => {
  res.json({
    message: 'My React Apps chat backend is running',
    status: 'ok'
  })
})

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', service: 'chat-backend' })
})

app.get('/api/users', async (_req, res) => {
  try {
    res.json(await readUsers())
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
      status: 'offline'
    }

    users.push(newUser)
    await writeUsers(users)

    res.status(201).json({ message: 'Registration successful', user: publicUser(newUser) })
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

    res.json({ message: 'Login successful', user: publicUser(user) })
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

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Chat backend running on port ${PORT}`)
})
