import { useEffect, useMemo, useRef, useState } from 'react'
import { io } from 'socket.io-client'
import { Navigate, Route, Routes, useLocation, useMatch, useNavigate } from 'react-router-dom'
import './App.css'
import LoginPage from './components/LoginPage'
import RegisterPage from './components/RegisterPage'
import Dashboard from './components/Dashboard'
import ChatScreen from './components/ChatScreen'

const API_URL = 'https://my-react-apps-aet5.onrender.com'

function ProtectedRoute({ user, children }) {
  if (!user) return <Navigate to="/login" replace />
  return children
}

function App() {
  const navigate = useNavigate()
  const location = useLocation()
  const chatMatch = useMatch('/chat/:userId')

  const [user, setUser] = useState(null)
  const [sessionReady, setSessionReady] = useState(false)
  const [users, setUsers] = useState([])
  const [unreadCounts, setUnreadCounts] = useState({})
  const [search, setSearch] = useState('')
  const [messages, setMessages] = useState([])
  const [conversationCache, setConversationCache] = useState({})
  const [text, setText] = useState('')
  const [notice, setNotice] = useState('')
  const [loading, setLoading] = useState(false)
  const [chatLoading, setChatLoading] = useState(false)
  const [socketConnected, setSocketConnected] = useState(false)
  const [token, setToken] = useState(() => localStorage.getItem('chatspace_token') || '')

  const socketRef = useRef(null)
  const selectedUserRef = useRef(null)

  useEffect(() => {
    try {
      const saved = localStorage.getItem('chatspace_user')
      const savedToken = localStorage.getItem('chatspace_token')
      if (saved && savedToken) {
        const parsed = JSON.parse(saved)
        if (parsed?.id) setUser(parsed)
      }
    } catch {
      localStorage.removeItem('chatspace_user')
    } finally {
      setSessionReady(true)
    }
  }, [])

  useEffect(() => {
    if (!sessionReady) return

    if (token) {
      fetch(API_URL + '/api/me', { headers: { Authorization: 'Bearer ' + token } })
        .then(async (response) => {
          if (!response.ok) throw new Error()
          const data = await response.json()
          setUser(data.user)
        })
        .catch(() => {
          localStorage.removeItem('chatspace_user')
          localStorage.removeItem('chatspace_token')
          setUser(null)
          setToken('')
        })
    } else {
      setUser(null)
    }

  }, [sessionReady, token])

  // Handle redirects separately so changing between Dashboard and Chat does
  // not revalidate the session or recreate the Socket.IO connection.
  useEffect(() => {
    const authRoute = location.pathname === '/login' || location.pathname === '/register'

    if (user && authRoute) {
      navigate('/dashboard', { replace: true })
    }
  }, [user, location.pathname, navigate])

  useEffect(() => {
    if (!sessionReady) return

    try {
      if (user && token) localStorage.setItem('chatspace_user', JSON.stringify(user))
      else localStorage.removeItem('chatspace_user')
    } catch {}
  }, [user, token, sessionReady])

  useEffect(() => {
    if (!user || !token) return

    let active = true

    async function loadUsersForSocket() {
      try {
        const response = await fetch(API_URL + '/api/users', {
          headers: { Authorization: 'Bearer ' + token },
        })
        if (!response.ok) return
        const data = await response.json()
        if (active) {
          const nextUsers = data.filter((item) => item.id !== user.id)
          setUsers((current) => {
            const currentKey = JSON.stringify(current)
            const nextKey = JSON.stringify(nextUsers)
            return currentKey === nextKey ? current : nextUsers
          })
          setUnreadCounts(
            Object.fromEntries(
              data
                .filter((item) => item.id !== user.id && item.unreadCount > 0)
                .map((item) => [item.id, item.unreadCount])
            )
          )
        }
      } catch {}
    }

    loadUsersForSocket()

    const socket = io(API_URL, {
      auth: { token },
      transports: ['websocket', 'polling'],
      reconnection: true,
      reconnectionAttempts: Infinity,
      reconnectionDelay: 1000,
    })

    socketRef.current = socket

    socket.on('connect', () => {
      setSocketConnected(true)
      setNotice('')
      loadUsersForSocket()
    })

    socket.on('connect_error', () => {
      setSocketConnected(false)
      setNotice('Reconnecting to ChatSpace…')
    })

    socket.on('disconnect', () => setSocketConnected(false))

    socket.on('user:status', ({ userId, status }) => {
      setUsers((current) =>
        current.map((item) => item.id === userId ? { ...item, status } : item)
      )
    })

    socket.on('private:message', (incoming) => {
      const openUser = selectedUserRef.current

      const otherUserId = incoming.senderId === user.id
        ? incoming.receiverId
        : incoming.senderId

      if (
        openUser &&
        ((incoming.senderId === user.id && incoming.receiverId === openUser.id) ||
          (incoming.senderId === openUser.id && incoming.receiverId === user.id))
      ) {
        setMessages((current) => {
          if (current.some((item) => item.id === incoming.id)) return current
          const next = [...current, incoming]
          setConversationCache((cache) => ({ ...cache, [otherUserId]: next }))
          return next
        })

        setUsers((current) =>
          current.map((item) =>
            item.id === otherUserId
              ? { ...item, latestMessageAt: incoming.createdAt }
              : item
          )
        )
      } else if (incoming.receiverId === user.id) {
        setUnreadCounts((current) => ({
          ...current,
          [otherUserId]: (current[otherUserId] || 0) + 1,
        }))

        setUsers((current) =>
          current.map((item) =>
            item.id === otherUserId
              ? { ...item, latestMessageAt: incoming.createdAt }
              : item
          )
        )
      }
    })

    return () => {
      active = false
      socket.removeAllListeners()
      socket.disconnect()
      socketRef.current = null
      setSocketConnected(false)
    }
  }, [user?.id, token])

  const selectedUser = useMemo(() => {
    if (!chatMatch?.params.userId) return null
    return users.find((item) => item.id === chatMatch.params.userId) || null
  }, [chatMatch?.params.userId, users])

  useEffect(() => {
    selectedUserRef.current = selectedUser
  }, [selectedUser])


  // Reconcile the open conversation after reconnects, tab switches, or missed
  // Socket.IO events. Socket.IO remains the primary real-time delivery path;
  // this is a lightweight reliability fallback so messages cannot silently
  // disappear when a mobile browser suspends a connection.
  useEffect(() => {
    if (!socketConnected || !selectedUser || !user) return

    let cancelled = false

    async function syncConversation() {
      try {
        const response = await fetch(
          API_URL + '/api/messages/' + user.id + '/' + selectedUser.id,
          { headers: { Authorization: 'Bearer ' + token } }
        )

        if (!response.ok) return

        const data = await response.json()
        if (cancelled) return

        setMessages((current) => {
          const byId = new Map(current.map((item) => [item.id, item]))

          for (const item of data.messages || []) {
            byId.set(item.id, item)
          }

          const next = [...byId.values()].sort(
            (a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime()
          )
          setConversationCache((cache) => ({
            ...cache,
            [selectedUser.id]: next,
          }))
          return next
        })
      } catch {}
    }

    syncConversation()

    const interval = window.setInterval(syncConversation, 5000)

    const handleVisibility = () => {
      if (document.visibilityState === 'visible') {
        syncConversation()
      }
    }

    document.addEventListener('visibilitychange', handleVisibility)

    return () => {
      cancelled = true
      window.clearInterval(interval)
      document.removeEventListener('visibilitychange', handleVisibility)
    }
  }, [socketConnected, selectedUser?.id, user?.id, token])

  useEffect(() => {
    if (!selectedUser || !user) {
      setMessages([])
      setChatLoading(false)
      return
    }

    let cancelled = false
    const cachedMessages = conversationCache[selectedUser.id]

    // Show cached messages immediately when this conversation was already opened.
    // Only show the loading state when there is genuinely no cached conversation.
    setMessages(cachedMessages || [])
    setChatLoading(!cachedMessages)
    setText('')

    async function loadMessages() {
      try {
        const response = await fetch(
          API_URL + '/api/messages/' + user.id + '/' + selectedUser.id,
          { headers: { Authorization: 'Bearer ' + token } }
        )

        if (!response.ok) throw new Error()

        const data = await response.json()

        if (!cancelled) {
          const freshMessages = data.messages || []
          setMessages(freshMessages)
          setConversationCache((current) => ({
            ...current,
            [selectedUser.id]: freshMessages,
          }))
          setChatLoading(false)
        }
      } catch {
        if (!cancelled) setChatLoading(false)
      }
    }

    loadMessages()

    return () => {
      cancelled = true
    }
  }, [selectedUser?.id, user?.id, token])

  async function submitLogin(credentials) {
    setNotice('')
    setLoading(true)

    try {
      const response = await fetch(API_URL + '/api/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(credentials),
      })

      const data = await response.json()

      if (!response.ok) throw new Error(data.error || 'Sign in failed')

      setUser(data.user)
      setToken(data.token)
      localStorage.setItem('chatspace_token', data.token)
      navigate('/dashboard', { replace: true })
    } catch (error) {
      setNotice(error.message)
    } finally {
      setLoading(false)
    }
  }

  async function submitRegister(form) {
    setNotice('')
    setLoading(true)

    try {
      const response = await fetch(API_URL + '/api/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      })

      const data = await response.json()

      if (!response.ok) throw new Error(data.error || 'Registration failed')

      setUser(data.user)
      setToken(data.token)
      localStorage.setItem('chatspace_token', data.token)
      navigate('/dashboard', { replace: true })
    } catch (error) {
      setNotice(error.message)
    } finally {
      setLoading(false)
    }
  }

  function openChat(userId) {
    setUnreadCounts((current) => {
      if (!current[userId]) return current
      const next = { ...current }
      delete next[userId]
      return next
    })
    navigate('/chat/' + encodeURIComponent(userId))
  }

  function sendMessage(e) {
    e?.preventDefault()

    const trimmed = text.trim()

    if (!trimmed || !selectedUser || !socketRef.current?.connected) return

    socketRef.current.emit(
      'private:message',
      { receiverId: selectedUser.id, text: trimmed },
      (result) => {
        if (!result?.ok) {
          setNotice(result?.error || 'Could not send message')
        } else {
          setText('')
          setNotice('')
        }
      }
    )
  }

  async function logout() {
    const currentToken = token

    try {
      if (currentToken) {
        await fetch(API_URL + '/api/logout', {
          method: 'POST',
          headers: { Authorization: 'Bearer ' + currentToken },
        })
      }
    } catch {}

    try {
      localStorage.removeItem('chatspace_user')
      localStorage.removeItem('chatspace_token')
    } catch {}

    socketRef.current?.disconnect()

    setToken('')
    setUser(null)
    setUsers([])
    setUnreadCounts({})
    setMessages([])
    setConversationCache({})
    setText('')
    setSearch('')
    setSocketConnected(false)

    navigate('/login', { replace: true })
  }

  const onlineCount = users.filter((item) => item.status === 'online').length

  if (!sessionReady) {
    return <div className="boot-screen">Loading ChatSpace…</div>
  }

  return (
    <Routes>
      <Route
        path="/"
        element={<Navigate to={user ? '/dashboard' : '/login'} replace />}
      />

      <Route
        path="/login"
        element={
          user ? (
            <Navigate to="/dashboard" replace />
          ) : (
            <LoginPage
              loading={loading}
              notice={notice}
              onSubmit={submitLogin}
              onRegister={() => {
                setNotice('')
                navigate('/register')
              }}
            />
          )
        }
      />

      <Route
        path="/register"
        element={
          user ? (
            <Navigate to="/dashboard" replace />
          ) : (
            <RegisterPage
              loading={loading}
              notice={notice}
              onSubmit={submitRegister}
              onLogin={() => {
                setNotice('')
                navigate('/login')
              }}
            />
          )
        }
      />

      <Route
        path="/dashboard"
        element={
          <ProtectedRoute user={user}>
            <Dashboard
              user={user}
              users={users}
              search={search}
              setSearch={setSearch}
              onlineCount={onlineCount}
              openUser={openChat}
              unreadCounts={unreadCounts}
              socketConnected={socketConnected}
              onLogout={logout}
            />
          </ProtectedRoute>
        }
      />

      <Route
        path="/chat/:userId"
        element={
          <ProtectedRoute user={user}>
            <ChatScreen
              user={user}
              selectedUser={selectedUser}
              messages={messages}
              text={text}
              setText={setText}
              notice={notice}
              chatLoading={chatLoading}
              socketConnected={socketConnected}
              sendMessage={sendMessage}
              onBack={() => navigate('/dashboard')}
            />
          </ProtectedRoute>
        }
      />

      <Route
        path="*"
        element={<Navigate to={user ? '/dashboard' : '/login'} replace />}
      />
    </Routes>
  )
}

export default App
