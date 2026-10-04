import { useEffect, useMemo, useRef, useState } from 'react'
import { io } from 'socket.io-client'
import './App.css'
import Dashboard from './components/Dashboard'
import ChatScreen from './components/ChatScreen'

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
  const [hasSession, setHasSession] = useState(false)
  const [hasMoreMessages, setHasMoreMessages] = useState(false)
  const [loadingOlder, setLoadingOlder] = useState(false)
  const socketRef = useRef(null)
  const selectedUserRef = useRef(null)
  const bottomRef = useRef(null)
  const inputRef = useRef(null)
  const sessionRestoredRef = useRef(false)
  const preserveScrollRef = useRef(false)

  useEffect(() => {
    selectedUserRef.current = selectedUser
  }, [selectedUser])

  useEffect(() => {
    try {
      const savedUser = sessionStorage.getItem('chatspace_user')
      if (savedUser) {
        const parsedUser = JSON.parse(savedUser)
        if (parsedUser?.id) {
          sessionRestoredRef.current = true
          setUser(parsedUser)
        }
      }
    } catch {
      sessionStorage.removeItem('chatspace_user')
    } finally {
      setHasSession(true)
    }
  }, [])

  useEffect(() => {
    if (!hasSession) return
    try {
      if (user) sessionStorage.setItem('chatspace_user', JSON.stringify(user))
      else if (!sessionRestoredRef.current) sessionStorage.removeItem('chatspace_user')
    } catch {}
  }, [user, hasSession])

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
        if (!cancelled) {
          setMessages(data.messages || [])
          setHasMoreMessages(Boolean(data.hasMore))
        }
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
    if (preserveScrollRef.current) {
      preserveScrollRef.current = false
      return
    }
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
    setHasMoreMessages(false)
    setMobileUsersOpen(false)
  }

  async function loadOlderMessages() {
    if (!selectedUser || !user || loadingOlder || !hasMoreMessages || !messages.length) return

    const oldest = messages[0]?.createdAt
    if (!oldest) return

    const container = document.querySelector('.messages-area')
    const previousHeight = container?.scrollHeight || 0

    setLoadingOlder(true)
    try {
      const response = await fetch(
        API_URL + '/api/messages/' + user.id + '/' + selectedUser.id +
        '?limit=40&before=' + encodeURIComponent(oldest),
      )
      if (!response.ok) throw new Error()

      const data = await response.json()
      const older = data.messages || []

      if (older.length) {
        preserveScrollRef.current = true
        setMessages((current) => [...older, ...current])
        setHasMoreMessages(Boolean(data.hasMore))
        requestAnimationFrame(() => {
          if (container) container.scrollTop = container.scrollHeight - previousHeight
        })
      } else {
        setHasMoreMessages(false)
      }
    } catch {
      setNotice('Could not load older messages.')
    } finally {
      setLoadingOlder(false)
    }
  }

  function handleMessagesScroll(e) {
    if (e.currentTarget.scrollTop < 80 && hasMoreMessages && !loadingOlder) {
      loadOlderMessages()
    }
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
    try { sessionStorage.removeItem('chatspace_user') } catch {}
    sessionRestoredRef.current = false
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

  if (!hasSession) return null


  if (!hasSession) return null

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
          <Dashboard
            users={users}
            selectedUser={selectedUser}
            search={search}
            setSearch={setSearch}
            onlineCount={onlineCount}
            openUser={openUser}
            loadUsers={loadUsers}
            mobileUsersOpen={mobileUsersOpen}
            setMobileUsersOpen={setMobileUsersOpen}
            Avatar={Avatar}
            Icon={Icon}
          />
          <ChatScreen
            user={user}
            selectedUser={selectedUser}
            messages={messages}
            text={text}
            setText={setText}
            notice={notice}
            chatLoading={chatLoading}
            socketConnected={socketConnected}
            hasMoreMessages={hasMoreMessages}
            loadingOlder={loadingOlder}
            handleMessagesScroll={handleMessagesScroll}
            sendMessage={sendMessage}
            inputRef={inputRef}
            bottomRef={bottomRef}
            setMobileUsersOpen={setMobileUsersOpen}
            Avatar={Avatar}
            Icon={Icon}
          />
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
                <button className="dialog-cancel" onClick={() => setShowLogoutDialog(false)}>Cancel</button>
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
