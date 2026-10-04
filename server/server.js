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

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Chat backend running on port ${PORT}`)
})
