import { useState } from 'react'
import './App.css'

const API_URL = 'https://my-react-apps-aet5.onrender.com'

function App() {
  const [mode, setMode] = useState('login')
  const [form, setForm] = useState({ name: '', username: '', password: '', phone: '' })
  const [user, setUser] = useState(null)
  const [message, setMessage] = useState('')
  const [loading, setLoading] = useState(false)

  function updateField(e) {
    setForm({ ...form, [e.target.name]: e.target.value })
  }

  async function submit(e) {
    e.preventDefault()
    setMessage('')
    setLoading(true)
    try {
      const endpoint = mode === 'login' ? '/api/login' : '/api/register'
      const body = mode === 'login'
        ? { username: form.username, password: form.password }
        : form

      const response = await fetch(API_URL + endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'Something went wrong')

      setUser(data.user)
      setMessage(mode === 'login' ? 'Login successful!' : 'Account created successfully!')
      setForm({ name: '', username: '', password: '', phone: '' })
    } catch (error) {
      setMessage(error.message)
    } finally {
      setLoading(false)
    }
  }

  async function logout() {
    await fetch(API_URL + '/api/logout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ userId: user.id }),
    })
    setUser(null)
    setMessage('')
  }

  if (user) {
    return (
      <main className="app-shell">
        <section className="dashboard-card">
          <div className="brand">ChatSpace</div>
          <div className="avatar">{user.name.charAt(0).toUpperCase()}</div>
          <h1>Welcome, {user.name} 👋</h1>
          <p className="subtitle">Your account is connected to the chat backend.</p>
          <div className="user-info">
            <div><span>Name</span><strong>{user.name}</strong></div>
            <div><span>Email</span><strong>{user.username}</strong></div>
            <div><span>Phone</span><strong>{user.phone || 'Not added'}</strong></div>
            <div><span>Status</span><strong className="online">● Online</strong></div>
          </div>
          <button className="secondary-button" onClick={logout}>Log out</button>
        </section>
      </main>
    )
  }

  return (
    <main className="app-shell">
      <section className="auth-card">
        <div className="brand">ChatSpace</div>
        <h1>{mode === 'login' ? 'Welcome back' : 'Create your account'}</h1>
        <p className="subtitle">
          {mode === 'login' ? 'Sign in to continue to your chats.' : 'Create an account to start chatting.'}
        </p>

        <div className="tabs">
          <button className={mode === 'login' ? 'active' : ''} onClick={() => setMode('login')}>Login</button>
          <button className={mode === 'register' ? 'active' : ''} onClick={() => setMode('register')}>Register</button>
        </div>

        <form onSubmit={submit}>
          {mode === 'register' && (
            <>
              <label>Name
                <input name="name" value={form.name} onChange={updateField} placeholder="Enter your name" />
              </label>
              <label>Phone number <span>(optional)</span>
                <input name="phone" value={form.phone} onChange={updateField} placeholder="Enter phone number" />
              </label>
            </>
          )}

          <label>Email / Username
            <input name="username" type="email" value={form.username} onChange={updateField} placeholder="you@example.com" />
          </label>

          <label>Password
            <input name="password" type="password" value={form.password} onChange={updateField} placeholder="Minimum 6 characters" />
          </label>

          <button className="primary-button" disabled={loading}>
            {loading ? 'Please wait...' : mode === 'login' ? 'Login' : 'Create account'}
          </button>
        </form>

        {message && <p className={message.includes('successful') ? 'message success' : 'message error'}>{message}</p>}

        <p className="switch-text">
          {mode === 'login' ? "Don't have an account?" : 'Already have an account?'}{' '}
          <button type="button" className="link-button" onClick={() => setMode(mode === 'login' ? 'register' : 'login')}>
            {mode === 'login' ? 'Register' : 'Login'}
          </button>
        </p>
      </section>
    </main>
  )
}

export default App
