import { useEffect, useRef, useState } from 'react'
import { io } from 'socket.io-client'
import './App.css'

const API_URL = 'https://my-react-apps-aet5.onrender.com'

function App() {
  const [mode, setMode] = useState('login')
  const [form, setForm] = useState({ name: '', username: '', password: '', phone: '' })
  const [user, setUser] = useState(null)
  const [users, setUsers] = useState([])
  const [selectedUser, setSelectedUser] = useState(null)
  const [messages, setMessages] = useState([])
  const [text, setText] = useState('')
  const [message, setMessage] = useState('')
  const [loading, setLoading] = useState(false)
  const [chatLoading, setChatLoading] = useState(false)
  const [socketConnected, setSocketConnected] = useState(false)
  const socketRef = useRef(null)
  const selectedUserRef = useRef(null)
  const bottomRef = useRef(null)

  useEffect(() => {
    selectedUserRef.current = selectedUser
  }, [selectedUser])

  useEffect(() => {
    if (!user) return

    loadUsers()

    const socket = io(API_URL, {
      transports: ['websocket', 'polling'],
      reconnection: true,
      reconnectionAttempts: Infinity,
      reconnectionDelay: 1000,
    })

    socketRef.current = socket

    socket.on('connect', () => {
      setSocketConnected(true)
      setMessage('')
      socket.emit('user:online', user.id)
      loadUsers()
    })

    socket.on('connect_error', () => {
      setSocketConnected(false)
      setMessage('Real-time connection failed. Retrying...')
    })

    socket.on('disconnect', () => {
      setSocketConnected(false)
    })

    socket.on('user:status', ({ userId, status }) => {
      setUsers((current) =>
        current.map((item) => item.id === userId ? { ...item, status } : item),
      )

      setSelectedUser((current) =>
        current?.id === userId ? { ...current, status } : current,
      )
    })

    socket.on('private:message', (incoming) => {
      const openUser = selectedUserRef.current

      const belongsToOpenChat =
        openUser &&
        ((incoming.senderId === user.id && incoming.receiverId === openUser.id) ||
          (incoming.senderId === openUser.id && incoming.receiverId === user.id))

      if (belongsToOpenChat) {
        setMessages((current) =>
          current.some((item) => item.id === incoming.id)
            ? current
            : [...current, incoming],
        )
      }
    })

    return () => {
      socket.removeAllListeners()
      socket.disconnect()
      socketRef.current = null
      setSocketConnected(false)
    }
  }, [user])

  useEffect(() => {
    if (!selectedUser || !user) return

    let cancelled = false

    async function loadMessages() {
      setChatLoading(true)

      try {
        const response = await fetch(
          API_URL + '/api/messages/' + user.id + '/' + selectedUser.id,
        )

        if (!response.ok) throw new Error('Could not load messages')

        const data = await response.json()

        if (!cancelled) {
          setMessages(data)
        }
      } catch {
        if (!cancelled) setMessages([])
      } finally {
        if (!cancelled) setChatLoading(false)
      }
    }

    loadMessages()

    return () => {
      cancelled = true
    }
  }, [selectedUser, user])

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  async function loadUsers() {
    try {
      const response = await fetch(API_URL + '/api/users')

      if (!response.ok) return

      const data = await response.json()

      setUsers((current) => {
        const currentMap = new Map(current.map((item) => [item.id, item]))
        return data
          .filter((item) => item.id !== user?.id)
          .map((item) => ({
            ...item,
            status: currentMap.get(item.id)?.status ?? item.status,
          }))
      })
    } catch {
      // Keep the current list if the backend is temporarily unavailable.
    }
  }

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

      if (!response.ok) {
        throw new Error(data.error || 'Something went wrong')
      }

      setUser(data.user)
      setMessage(mode === 'login' ? 'Login successful!' : 'Account created successfully!')
      setForm({ name: '', username: '', password: '', phone: '' })
    } catch (error) {
      setMessage(error.message)
    } finally {
      setLoading(false)
    }
  }

  function sendMessage(e) {
    e?.preventDefault()

    const trimmed = text.trim()

    if (!trimmed || !selectedUser || !socketRef.current?.connected) return

    socketRef.current.emit(
      'private:message',
      {
        receiverId: selectedUser.id,
        text: trimmed,
      },
      (result) => {
        if (!result?.ok) {
          setMessage(result?.error || 'Could not send message')
        } else {
          setText('')
          setMessage('')
        }
      },
    )
  }

  async function logout() {
    socketRef.current?.disconnect()

    try {
      await fetch(API_URL + '/api/logout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ userId: user.id }),
      })
    } catch {
      // Socket disconnect also marks the user offline.
    }

    setUser(null)
    setUsers([])
    setSelectedUser(null)
    setMessages([])
    setText('')
    setSocketConnected(false)
    setMessage('')
  }

  if (user) {
    return (
      <main className="chat-app">
        <header className="chat-header">
          <div>
            <div className="brand">ChatSpace</div>
            <div className="logged-in-as">
              Logged in as <strong>{user.name}</strong>
              <span className={socketConnected ? 'connection online' : 'connection'}>
                ● {socketConnected ? 'connected' : 'connecting'}
              </span>
            </div>
          </div>

          <button className="logout-button" onClick={logout}>Logout</button>
        </header>

        <section className="chat-layout">
          <aside className="users-panel">
            <div className="panel-title">
              <h2>Users</h2>
              <button onClick={loadUsers}>Refresh</button>
            </div>

            {users.length === 0 ? (
              <p className="empty">No other users found.</p>
            ) : (
              <div className="user-list">
                {users.map((item) => (
                  <button
                    key={item.id}
                    className={selectedUser?.id === item.id ? 'user-item selected' : 'user-item'}
                    onClick={() => {
                      setSelectedUser(item)
                      setMessages([])
                    }}
                  >
                    <span className="small-avatar">
                      {item.name.charAt(0).toUpperCase()}
                    </span>

                    <span className="user-details">
                      <strong>{item.name}</strong>
                      <small>{item.username}</small>
                      <em className={item.status === 'online' ? 'status online' : 'status'}>
                        ● {item.status}
                      </em>
                    </span>
                  </button>
                ))}
              </div>
            )}
          </aside>

          <section className="chat-window">
            {selectedUser ? (
              <>
                <header className="conversation-header">
                  <div className="selected-avatar small">
                    {selectedUser.name.charAt(0).toUpperCase()}
                  </div>

                  <div>
                    <h2>{selectedUser.name}</h2>
                    <p className={selectedUser.status === 'online' ? 'status online' : 'status'}>
                      ● {selectedUser.status}
                    </p>
                  </div>
                </header>

                <div className="messages-area">
                  {chatLoading ? (
                    <p className="chat-info">Loading messages...</p>
                  ) : messages.length === 0 ? (
                    <p className="chat-info">No messages yet. Say hello! 👋</p>
                  ) : (
                    messages.map((item) => (
                      <div
                        key={item.id}
                        className={item.senderId === user.id ? 'message-row mine' : 'message-row'}
                      >
                        <div className="message-bubble">
                          <span>{item.text}</span>
                          <small>
                            {new Date(item.createdAt).toLocaleTimeString([], {
                              hour: '2-digit',
                              minute: '2-digit',
                            })}
                          </small>
                        </div>
                      </div>
                    ))
                  )}

                  <div ref={bottomRef} />
                </div>

                <form className="message-form" onSubmit={sendMessage}>
                  <input
                    value={text}
                    onChange={(e) => setText(e.target.value)}
                    placeholder={socketConnected ? 'Type a message...' : 'Connecting...'}
                    maxLength={2000}
                    disabled={!socketConnected}
                  />

                  <button type="submit" disabled={!socketConnected || !text.trim()}>
                    Send
                  </button>
                </form>
              </>
            ) : (
              <div className="chat-placeholder">
                <div className="chat-icon">💬</div>
                <h2>Select a user</h2>
                <p>Choose someone from the list to start a conversation.</p>
              </div>
            )}
          </section>
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
          {mode === 'login'
            ? 'Sign in to continue to your chats.'
            : 'Create an account to start chatting.'}
        </p>

        <div className="tabs">
          <button
            className={mode === 'login' ? 'active' : ''}
            onClick={() => setMode('login')}
          >
            Login
          </button>

          <button
            className={mode === 'register' ? 'active' : ''}
            onClick={() => setMode('register')}
          >
            Register
          </button>
        </div>

        <form onSubmit={submit}>
          {mode === 'register' && (
            <>
              <label>
                Name
                <input
                  name="name"
                  value={form.name}
                  onChange={updateField}
                  placeholder="Enter your name"
                />
              </label>

              <label>
                Phone number <span>(optional)</span>
                <input
                  name="phone"
                  value={form.phone}
                  onChange={updateField}
                  placeholder="Enter phone number"
                />
              </label>
            </>
          )}

          <label>
            Email / Username
            <input
              name="username"
              type="email"
              value={form.username}
              onChange={updateField}
              placeholder="you@example.com"
            />
          </label>

          <label>
            Password
            <input
              name="password"
              type="password"
              value={form.password}
              onChange={updateField}
              placeholder="Minimum 6 characters"
            />
          </label>

          <button className="primary-button" disabled={loading}>
            {loading
              ? 'Please wait...'
              : mode === 'login'
                ? 'Login'
                : 'Create account'}
          </button>
        </form>

        {message && (
          <p className={message.includes('successful') ? 'message success' : 'message error'}>
            {message}
          </p>
        )}

        <p className="switch-text">
          {mode === 'login'
            ? "Don't have an account?"
            : 'Already have an account?'}{' '}

          <button
            type="button"
            className="link-button"
            onClick={() => setMode(mode === 'login' ? 'register' : 'login')}
          >
            {mode === 'login' ? 'Register' : 'Login'}
          </button>
        </p>
      </section>
    </main>
  )
}

export default App
