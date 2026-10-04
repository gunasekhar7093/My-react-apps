import { useEffect, useMemo, useRef, useState } from 'react'
import { io } from 'socket.io-client'
import './App.css'

const API_URL = 'https://my-react-apps-aet5.onrender.com'

function Avatar({ name, size = 'md', online = false }) {
  return (
    <span className={`avatar avatar-${size}`}>
      {name?.charAt(0).toUpperCase() || '?'}
      {online && <span className="avatar-dot" />}
    </span>
  )
}

function Icon({ name }) {
  const paths = {
    search: <><circle cx="11" cy="11" r="7" /><path d="m20 20-4-4" /></>,
    send: <><path d="m22 2-7 20-4-9-9-4Z" /><path d="M22 2 11 13" /></>,
    logout: <><path d="M10 17l5-5-5-5" /><path d="M15 12H3" /><path d="M21 19V5a2 2 0 0 0-2-2h-5" /></>,
    refresh: <><path d="M20 11a8 8 0 1 0 2 5" /><path d="M20 4v7h-7" /></>,
    menu: <><path d="M4 6h16M4 12h16M4 18h16" /></>,
    close: <><path d="m6 6 12 12M18 6 6 18" /></>,
    message: <><path d="M21 11.5a8.4 8.4 0 0 1-9 8.5 9.7 9.7 0 0 1-4-.9L3 21l1.8-4.4A8.3 8.3 0 0 1 3 11.5 8.5 8.5 0 0 1 12 3a8.5 8.5 0 0 1 9 8.5Z" /></>,
  }

  return <svg className="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">{paths[name]}</svg>
}

function App() {
  const [mode, setMode] = useState('login')
  const [form, setForm] = useState({ name: '', username: '', password: '', phone: '' })
  const [user, setUser] = useState(null)
  const [users, setUsers] = useState([])
  const [selectedUser, setSelectedUser] = useState(null)
  const [messages, setMessages] = useState([])
  const [text, setText] = useState('')
  const [notice, setNotice] = useState('')
  const [loading, setLoading] = useState(false)
  const [chatLoading, setChatLoading] = useState(false)
  const [socketConnected, setSocketConnected] = useState(false)
  const [search, setSearch] = useState('')
  const [mobileUsersOpen, setMobileUsersOpen] = useState(true)
  const [showLogoutDialog, setShowLogoutDialog] = useState(false)
  const socketRef = useRef(null)
  const selectedUserRef = useRef(null)
  const bottomRef = useRef(null)
  const inputRef = useRef(null)

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
      setNotice('')
      socket.emit('user:online', user.id)
      loadUsers()
    })

    socket.on('connect_error', () => {
      setSocketConnected(false)
      setNotice('Reconnecting to ChatSpace…')
    })

    socket.on('disconnect', () => setSocketConnected(false))

    socket.on('user:status', ({ userId, status }) => {
      setUsers((current) => current.map((item) => item.id === userId ? { ...item, status } : item))
      setSelectedUser((current) => current?.id === userId ? { ...current, status } : current)
    })

    socket.on('private:message', (incoming) => {
      const openUser = selectedUserRef.current
      const belongsToOpenChat = openUser &&
        ((incoming.senderId === user.id && incoming.receiverId === openUser.id) ||
          (incoming.senderId === openUser.id && incoming.receiverId === user.id))

      if (belongsToOpenChat) {
        setMessages((current) => current.some((item) => item.id === incoming.id) ? current : [...current, incoming])
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
        const response = await fetch(API_URL + '/api/messages/' + user.id + '/' + selectedUser.id)
        if (!response.ok) throw new Error()
        const data = await response.json()
        if (!cancelled) setMessages(data)
      } catch {
        if (!cancelled) setMessages([])
      } finally {
        if (!cancelled) setChatLoading(false)
      }
    }

    loadMessages()
    setTimeout(() => inputRef.current?.focus(), 100)
    return () => { cancelled = true }
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
        const map = new Map(current.map((item) => [item.id, item]))
        return data.filter((item) => item.id !== user?.id).map((item) => ({
          ...item,
          status: map.get(item.id)?.status ?? item.status,
        }))
      })
    } catch {}
  }

  function updateField(e) {
    setForm((current) => ({ ...current, [e.target.name]: e.target.value }))
  }

  async function submit(e) {
    e.preventDefault()
    setNotice('')
    setLoading(true)

    try {
      const endpoint = mode === 'login' ? '/api/login' : '/api/register'
      const body = mode === 'login' ? { username: form.username, password: form.password } : form
      const response = await fetch(API_URL + endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'Something went wrong')
      setUser(data.user)
      setForm({ name: '', username: '', password: '', phone: '' })
    } catch (error) {
      setNotice(error.message)
    } finally {
      setLoading(false)
    }
  }

  function openUser(item) {
    setSelectedUser(item)
    setMessages([])
    setMobileUsersOpen(false)
  }

  function sendMessage(e) {
    e?.preventDefault()
    const trimmed = text.trim()
    if (!trimmed || !selectedUser || !socketRef.current?.connected) return

    socketRef.current.emit('private:message', { receiverId: selectedUser.id, text: trimmed }, (result) => {
      if (!result?.ok) {
        setNotice(result?.error || 'Could not send message')
      } else {
        setText('')
        setNotice('')
      }
    })
  }

  async function logout() {
    socketRef.current?.disconnect()
    try {
      await fetch(API_URL + '/api/logout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ userId: user.id }),
      })
    } catch {}

    setUser(null)
    setUsers([])
    setSelectedUser(null)
    setMessages([])
    setText('')
    setSearch('')
    setSocketConnected(false)
  }

  const filteredUsers = useMemo(() => {
    const query = search.trim().toLowerCase()
    if (!query) return users
    return users.filter((item) => item.name.toLowerCase().includes(query) || item.username.toLowerCase().includes(query))
  }, [users, search])

  const onlineCount = users.filter((item) => item.status === 'online').length

  if (user) {
    return (
      <main className="chat-app">
        <header className="topbar">
          <div className="topbar-brand">
            <div className="brand-mark"><Icon name="message" /></div>
            <div>
              <strong>ChatSpace</strong>
              <span>Private conversations</span>
            </div>
          </div>

          <div className="topbar-actions">
            <div className={`connection-pill ${socketConnected ? 'connected' : ''}`}>
              <span />
              {socketConnected ? 'Connected' : 'Reconnecting'}
            </div>
            <div className="account-chip">
              <Avatar name={user.name} size="sm" online={socketConnected} />
              <span>{user.name}</span>
            </div>
            <button className="icon-button logout-icon" onClick={() => setShowLogoutDialog(true)} aria-label="Logout" title="Logout">
              <Icon name="logout" />
            </button>
          </div>
        </header>

        <section className="workspace">
          <aside className={`users-panel ${mobileUsersOpen ? 'mobile-open' : ''}`}>
            <div className="sidebar-heading">
              <div>
                <span className="eyebrow">DIRECT MESSAGES</span>
                <h1>People</h1>
                <p>{users.length} {users.length === 1 ? 'person' : 'people'} · {onlineCount} online</p>
              </div>
              <button className="icon-button mobile-close" onClick={() => setMobileUsersOpen(false)} aria-label="Close people">
                <Icon name="close" />
              </button>
            </div>

            <div className="search-box">
              <Icon name="search" />
              <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search people" />
              {search && <button onClick={() => setSearch('')} aria-label="Clear search"><Icon name="close" /></button>}
            </div>

            <div className="people-list">
              {filteredUsers.map((item) => (
                <button key={item.id} className={selectedUser?.id === item.id ? 'person selected' : 'person'} onClick={() => openUser(item)}>
                  <Avatar name={item.name} size="lg" online={item.status === 'online'} />
                  <span className="person-copy">
                    <strong>{item.name}</strong>
                    <small>{item.status === 'online' ? 'Online now' : 'Offline'}</small>
                  </span>
                  <span className="person-arrow">›</span>
                </button>
              ))}

              {filteredUsers.length === 0 && (
                <div className="empty-people">
                  <div className="empty-icon"><Icon name="search" /></div>
                  <strong>{users.length ? 'No matches' : 'No other people yet'}</strong>
                  <span>{users.length ? 'Try another name or email.' : 'Create another account to start chatting.'}</span>
                </div>
              )}
            </div>

            <button className="refresh-button" onClick={loadUsers}>
              <Icon name="refresh" /> Refresh people
            </button>
          </aside>

          <section className="conversation">
            {selectedUser ? (
              <>
                <header className="conversation-header">
                  <button className="mobile-menu-button" onClick={() => setMobileUsersOpen(true)} aria-label="Open people">
                    <Icon name="menu" />
                  </button>
                  <Avatar name={selectedUser.name} size="lg" online={selectedUser.status === 'online'} />
                  <div className="conversation-person">
                    <h2>{selectedUser.name}</h2>
                    <span className={selectedUser.status === 'online' ? 'presence online' : 'presence'}>
                      {selectedUser.status === 'online' ? 'Active now' : 'Offline'}
                    </span>
                  </div>
                </header>

                <div className="messages-area">
                  {chatLoading ? (
                    <div className="chat-state"><span className="spinner" /> Loading conversation…</div>
                  ) : messages.length === 0 ? (
                    <div className="welcome-chat">
                      <Avatar name={selectedUser.name} size="xl" online={selectedUser.status === 'online'} />
                      <span className="eyebrow">PRIVATE CONVERSATION</span>
                      <h3>Say hello to {selectedUser.name.split(' ')[0]}</h3>
                      <p>Messages you send here are visible only to you and {selectedUser.name}.</p>
                    </div>
                  ) : (
                    <>
                      <div className="day-divider"><span>Conversation</span></div>
                      {messages.map((item) => (
                        <div key={item.id} className={item.senderId === user.id ? 'message-row mine' : 'message-row'}>
                          <div className="message-bubble">
                            <span>{item.text}</span>
                            <small>{new Date(item.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</small>
                          </div>
                        </div>
                      ))}
                    </>
                  )}
                  <div ref={bottomRef} />
                </div>

                {notice && <div className="chat-notice">{notice}</div>}

                <form className="message-form" onSubmit={sendMessage}>
                  <div className="composer">
                    <input
                      ref={inputRef}
                      value={text}
                      onChange={(e) => setText(e.target.value)}
                      placeholder={socketConnected ? 'Write a message…' : 'Connecting to ChatSpace…'}
                      maxLength={2000}
                      disabled={!socketConnected}
                      aria-label="Message"
                    />
                    <button className="send-button" type="submit" disabled={!socketConnected || !text.trim()} aria-label="Send message">
                      <Icon name="send" />
                    </button>
                  </div>
                  <span className="composer-hint">Enter to send · Messages are private</span>
                </form>
              </>
            ) : (
              <div className="no-chat">
                <button className="mobile-menu-button mobile-only-menu" onClick={() => setMobileUsersOpen(true)} aria-label="Open people">
                  <Icon name="menu" />
                </button>
                <div className="no-chat-icon"><Icon name="message" /></div>
                <span className="eyebrow">YOUR PRIVATE SPACE</span>
                <h2>Choose someone to start chatting</h2>
                <p>Select a person from the left to open a private conversation.</p>
                <button className="primary-action" onClick={() => setMobileUsersOpen(true)}>Browse people</button>
              </div>
            )}
          </section>
        </section>

        {showLogoutDialog && (
          <div className="dialog-backdrop" role="presentation" onMouseDown={() => setShowLogoutDialog(false)}>
            <section
              className="logout-dialog"
              role="dialog"
              aria-modal="true"
              aria-labelledby="logout-dialog-title"
              onMouseDown={(e) => e.stopPropagation()}
            >
              <div className="dialog-icon">
                <Icon name="logout" />
              </div>
              <div className="dialog-content">
                <h2 id="logout-dialog-title">Log out of ChatSpace?</h2>
                <p>You will be disconnected from your current conversation. You can sign in again anytime.</p>
              </div>
              <div className="dialog-actions">
                <button className="dialog-cancel" onClick={() => setShowLogoutDialog(false)}>
                  Cancel
                </button>
                <button
                  className="dialog-confirm"
                  onClick={() => {
                    setShowLogoutDialog(false)
                    logout()
                  }}
                >
                  Log out
                </button>
              </div>
            </section>
          </div>
        )}
      </main>
    )
  }

  return (
    <main className="auth-page">
      <div className="auth-decoration decoration-one" />
      <div className="auth-decoration decoration-two" />
      <section className="auth-layout">
        <div className="auth-showcase">
          <div className="showcase-brand"><div className="brand-mark"><Icon name="message" /></div><strong>ChatSpace</strong></div>
          <div className="showcase-copy">
            <span className="eyebrow">PRIVATE · SIMPLE · REAL-TIME</span>
            <h1>Conversations that feel <em>effortless.</em></h1>
            <p>Connect with people and have private conversations in a clean, focused space designed for everyday messaging.</p>
          </div>
          <div className="showcase-card">
            <div className="mini-avatars"><Avatar name="A" size="sm" online /><Avatar name="G" size="sm" online /><Avatar name="M" size="sm" /></div>
            <div><strong>Real-time conversations</strong><span>Messages delivered instantly</span></div>
            <span className="live-badge">LIVE</span>
          </div>
        </div>

        <section className="auth-card">
          <div className="auth-heading">
            <span className="eyebrow">{mode === 'login' ? 'WELCOME BACK' : 'GET STARTED'}</span>
            <h2>{mode === 'login' ? 'Sign in to ChatSpace' : 'Create your account'}</h2>
            <p>{mode === 'login' ? 'Enter your details to continue.' : 'It only takes a minute to get started.'}</p>
          </div>

          <div className="auth-tabs">
            <button className={mode === 'login' ? 'active' : ''} onClick={() => { setMode('login'); setNotice('') }}>Sign in</button>
            <button className={mode === 'register' ? 'active' : ''} onClick={() => { setMode('register'); setNotice('') }}>Create account</button>
          </div>

          <form className="auth-form" onSubmit={submit}>
            {mode === 'register' && (
              <>
                <label>Full name<input name="name" value={form.name} onChange={updateField} placeholder="Your name" autoComplete="name" required /></label>
                <label>Phone <span>Optional</span><input name="phone" value={form.phone} onChange={updateField} placeholder="+91 98765 43210" autoComplete="tel" /></label>
              </>
            )}
            <label>Email address<input name="username" type="email" value={form.username} onChange={updateField} placeholder="you@example.com" autoComplete="email" required /></label>
            <label>Password<input name="password" type="password" value={form.password} onChange={updateField} placeholder="At least 6 characters" autoComplete={mode === 'login' ? 'current-password' : 'new-password'} required /></label>

            <button className="auth-submit" disabled={loading}>
              {loading ? <><span className="spinner small" /> Please wait…</> : mode === 'login' ? 'Sign in' : 'Create account'}
            </button>
          </form>

          {notice && <div className="auth-notice">{notice}</div>}

          <p className="auth-switch">{mode === 'login' ? 'New to ChatSpace?' : 'Already have an account?'} <button onClick={() => setMode(mode === 'login' ? 'register' : 'login')}>{mode === 'login' ? 'Create account' : 'Sign in'}</button></p>
        </section>
      </section>
      <footer className="auth-footer">ChatSpace · Built for simple, private conversations</footer>
    </main>
  )
}

export default App
