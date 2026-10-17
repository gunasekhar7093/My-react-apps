import { useEffect, useMemo, useRef, useState } from 'react'
import { io } from 'socket.io-client'
import { Navigate, Route, Routes, useLocation, useMatch, useNavigate } from 'react-router-dom'
import './App.css'
import LoginPage from './components/LoginPage'
import RegisterPage from './components/RegisterPage'
import Dashboard from './components/Dashboard'
import ChatScreen from './components/ChatScreen'
import { playMessageChime } from './utils/sound'
import { requestNotificationPermission, showWebNotification } from './utils/notifications'

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
  const usersRef = useRef([])
  const conversationRequestRef = useRef(0)

  useEffect(() => {
    usersRef.current = users
  }, [users])

  useEffect(() => {
    if (user) {
      requestNotificationPermission()
    }
  }, [user])

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
      // Match the server's heartbeat timings (pingInterval:3s, pingTimeout:2s)
      // so the client aligns with the server's fast disconnect detection.
      pingTimeout: 2000,
      pingInterval: 3000,
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

    socket.on('user:status', ({ userId, status, lastSeenAt }) => {
      setUsers((current) =>
        current.map((item) => item.id === userId
          ? { ...item, status, ...(lastSeenAt ? { lastSeenAt } : {}) }
          : item
        )
      )
    })

    socket.on('private:message', (incoming) => {
      const openUser = selectedUserRef.current

      const otherUserId = incoming.senderId === user.id
        ? incoming.receiverId
        : incoming.senderId

      const isCurrentChat =
        openUser &&
        ((incoming.senderId === user.id && incoming.receiverId === openUser.id) ||
          (incoming.senderId === openUser.id && incoming.receiverId === user.id))

      if (isCurrentChat) {
        if (incoming.senderId !== user.id) {
          socket.emit('messages:delivered', { messageIds: [incoming.id] })
          socket.emit('messages:read', { senderId: otherUserId })
        }

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
        socket.emit('messages:delivered', { messageIds: [incoming.id] })
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

      // ── WhatsApp Notification for Incoming Message ────────────────────────
      if (incoming.receiverId === user.id && incoming.senderId !== user.id) {
        const isFocusedInThisChat = isCurrentChat && !document.hidden

        if (!isFocusedInThisChat) {
          const senderUser = usersRef.current?.find((u) => u.id === incoming.senderId)
          const senderName =
            incoming.senderName ||
            senderUser?.name ||
            senderUser?.username ||
            'New Message'

          let bodyText = incoming.text || ''
          if (!bodyText && incoming.mediaType) {
            bodyText =
              incoming.mediaType === 'image'
                ? '📷 Photo'
                : incoming.mediaType === 'video'
                ? '🎥 Video'
                : '📁 Attachment'
          } else if (incoming.mediaType === 'image') {
            bodyText = `📷 ${bodyText}`
          } else if (incoming.mediaType === 'video') {
            bodyText = `🎥 ${bodyText}`
          }

          // 1. Play WhatsApp chime
          playMessageChime()

          // 2. Desktop notification
          showWebNotification({
            title: senderName,
            body: bodyText,
            onClick: () => {
              openChat(incoming.senderId)
            },
          })
        }
      }
    })

    // ── Two White Ticks (✓✓): Recipient has opened and read the message ─────
    socket.on('messages:read', (data) => {
      if (!data?.readerId) return
      const readAt = data.readAt || new Date().toISOString()
      setMessages((current) =>
        current.map((msg) =>
          msg.senderId === user.id && (!msg.readAt || !msg.deliveredAt)
            ? { ...msg, readAt, deliveredAt: readAt, status: 'read' }
            : msg
        )
      )
    })

    // ── Two Gray Ticks (✓✓): Message delivered to recipient's device ────────
    socket.on('messages:delivered', (data) => {
      if (!data?.receiverId) return
      const deliveredAt = data.deliveredAt || new Date().toISOString()
      const ids = Array.isArray(data.messageIds) ? new Set(data.messageIds) : null
      setMessages((current) =>
        current.map((msg) =>
          msg.senderId === user.id && !msg.deliveredAt && (!ids || ids.has(msg.id))
            ? { ...msg, deliveredAt, status: 'delivered' }
            : msg
        )
      )
    })

    // ── Instant offline/online signaling ─────────────────────────────────────
    // Call /api/me/status immediately when the tab is hidden/shown or the
    // window is closed. This makes the status change visible to others
    // instantly instead of waiting for the ping/pong timeout (~5s fallback).
    const sendStatus = (status) => {
      try {
        // Use fetch with keepalive:true so the request completes even if the
        // page is closing (required for beforeunload handler on Chrome/Edge).
        fetch(API_URL + '/api/me/status', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: 'Bearer ' + token,
          },
          body: JSON.stringify({ status }),
          keepalive: true,
        }).catch(() => {})
      } catch (_) {}
    }

    const onVisibilityChange = () => {
      if (!active) return
      sendStatus(document.hidden ? 'offline' : 'online')
    }

    const onBeforeUnload = () => {
      sendStatus('offline')
    }

    document.addEventListener('visibilitychange', onVisibilityChange)
    window.addEventListener('beforeunload', onBeforeUnload)

    return () => {
      active = false
      document.removeEventListener('visibilitychange', onVisibilityChange)
      window.removeEventListener('beforeunload', onBeforeUnload)
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
          const incoming = data.messages || []
          const byId = new Map(current.map((item) => [item.id, item]))

          let hasNewOrChanged = false
          for (const item of incoming) {
            const existing = byId.get(item.id)
            if (!existing || existing.createdAt !== item.createdAt || existing.mediaUrl !== item.mediaUrl) {
              hasNewOrChanged = true
              byId.set(item.id, item)
            }
          }

          if (!hasNewOrChanged && byId.size === current.length) {
            return current
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

    const requestId = ++conversationRequestRef.current
    let cancelled = false
    const conversationId = selectedUser.id
    const cachedMessages = conversationCache[conversationId]

    // Show only this conversation's cache immediately. Older requests are not
    // allowed to overwrite the currently selected conversation.
    setMessages(cachedMessages || [])
    setChatLoading(!cachedMessages)
    setText('')

    async function loadMessages() {
      try {
        const response = await fetch(
          API_URL + '/api/messages/' + user.id + '/' + conversationId,
          { headers: { Authorization: 'Bearer ' + token } }
        )

        if (!response.ok) throw new Error()

        const data = await response.json()

        if (!cancelled && requestId === conversationRequestRef.current) {
          const freshMessages = data.messages || []
          setMessages((current) => {
            if (
              current.length === freshMessages.length &&
              current.every((item, idx) => item.id === freshMessages[idx]?.id)
            ) {
              return current
            }
            return freshMessages
          })
          setConversationCache((current) => ({
            ...current,
            [conversationId]: freshMessages,
          }))
          setChatLoading(false)
        }
      } catch {
        if (!cancelled && requestId === conversationRequestRef.current) {
          setChatLoading(false)
        }
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
    socketRef.current?.emit('messages:read', { senderId: userId })
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

  async function sendMedia({ file, caption }) {
    if (!file || !selectedUser || !socketRef.current?.connected) return

    setNotice('Uploading media to MongoDB…')
    try {
      const formData = new FormData()
      formData.append('file', file)

      const response = await fetch(API_URL + '/api/upload', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer ' + token,
        },
        body: formData,
      })

      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'Failed to upload media')

      socketRef.current.emit(
        'private:message',
        {
          receiverId: selectedUser.id,
          text: (caption || '').trim(),
          mediaUrl: data.mediaUrl,
          mediaType: data.mediaType,
          mediaName: data.mediaName,
          mediaSize: data.mediaSize,
        },
        (result) => {
          if (!result?.ok) {
            setNotice(result?.error || 'Could not send message')
          } else {
            setText('')
            setNotice('')
          }
        }
      )
    } catch (err) {
      setNotice(err.message || 'Media upload failed')
      throw err
    }
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
              sendMedia={sendMedia}
              apiUrl={API_URL}
              token={token}
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
