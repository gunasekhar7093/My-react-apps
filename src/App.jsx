import { useEffect, useMemo, useRef, useState } from 'react'
import { io } from 'socket.io-client'
import './App.css'
import LoginPage from './components/LoginPage'
import RegisterPage from './components/RegisterPage'
import Dashboard from './components/Dashboard'
import ChatScreen from './components/ChatScreen'

const API_URL = 'https://my-react-apps-aet5.onrender.com'

function routeFromPath(pathname) {
  const path = pathname.replace(/\/+$/, '') || '/'
  if (path === '/login' || path === '/') return { name: 'login' }
  if (path === '/register') return { name: 'register' }
  if (path === '/dashboard') return { name: 'dashboard' }
  const match = path.match(/^\/chat\/([^/]+)$/)
  if (match) return { name: 'chat', userId: decodeURIComponent(match[1]) }
  return { name: 'not-found' }
}

function App() {
  const [route, setRoute] = useState(() => routeFromPath(window.location.pathname))
  const [user, setUser] = useState(null)
  const [sessionReady, setSessionReady] = useState(false)
  const [users, setUsers] = useState([])
  const [search, setSearch] = useState('')
  const [messages, setMessages] = useState([])
  const [text, setText] = useState('')
  const [notice, setNotice] = useState('')
  const [loading, setLoading] = useState(false)
  const [chatLoading, setChatLoading] = useState(false)
  const [socketConnected, setSocketConnected] = useState(false)
  const socketRef = useRef(null)
  const selectedUserRef = useRef(null)

  function navigate(path, replace = false) {
    if (replace) window.history.replaceState({}, '', path)
    else window.history.pushState({}, '', path)
    setRoute(routeFromPath(path))
  }

  useEffect(() => {
    const pop = () => setRoute(routeFromPath(window.location.pathname))
    window.addEventListener('popstate', pop)
    return () => window.removeEventListener('popstate', pop)
  }, [])

  useEffect(() => {
    try {
      const saved = sessionStorage.getItem('chatspace_user')
      if (saved) {
        const parsed = JSON.parse(saved)
        if (parsed?.id) setUser(parsed)
      }
    } catch { sessionStorage.removeItem('chatspace_user') }
    finally { setSessionReady(true) }
  }, [])

  useEffect(() => {
    if (!sessionReady) return
    const protectedRoute = route.name === 'dashboard' || route.name === 'chat'
    const authRoute = route.name === 'login' || route.name === 'register'
    if (!user && protectedRoute) navigate('/login', true)
    else if (user && authRoute) navigate('/dashboard', true)
    else if (route.name === 'not-found') navigate(user ? '/dashboard' : '/login', true)
  }, [sessionReady, user, route.name])

  useEffect(() => {
    if (!sessionReady) return
    try {
      if (user) sessionStorage.setItem('chatspace_user', JSON.stringify(user))
      else sessionStorage.removeItem('chatspace_user')
    } catch {}
  }, [user, sessionReady])

  useEffect(() => {
    if (!user) return
    loadUsers()
    const socket = io(API_URL, { transports: ['websocket', 'polling'], reconnection: true, reconnectionAttempts: Infinity, reconnectionDelay: 1000 })
    socketRef.current = socket
    socket.on('connect', () => { setSocketConnected(true); setNotice(''); socket.emit('user:online', user.id); loadUsers() })
    socket.on('connect_error', () => { setSocketConnected(false); setNotice('Reconnecting to ChatSpace…') })
    socket.on('disconnect', () => setSocketConnected(false))
    socket.on('user:status', ({ userId, status }) => setUsers((current) => current.map((item) => item.id === userId ? { ...item, status } : item)))
    socket.on('private:message', (incoming) => {
      const openUser = selectedUserRef.current
      if (openUser && ((incoming.senderId === user.id && incoming.receiverId === openUser.id) || (incoming.senderId === openUser.id && incoming.receiverId === user.id))) {
        setMessages((current) => current.some((item) => item.id === incoming.id) ? current : [...current, incoming])
      }
    })
    return () => { socket.removeAllListeners(); socket.disconnect(); socketRef.current = null; setSocketConnected(false) }
  }, [user])

  const selectedUser = useMemo(() => route.name === 'chat' ? users.find((item) => item.id === route.userId) || null : null, [route, users])

  useEffect(() => { selectedUserRef.current = selectedUser }, [selectedUser])

  useEffect(() => {
    if (!selectedUser || !user) { setMessages([]); return }
    let cancelled = false
    async function loadMessages() {
      setChatLoading(true)
      try {
        const response = await fetch(API_URL + '/api/messages/' + user.id + '/' + selectedUser.id)
        if (!response.ok) throw new Error()
        const data = await response.json()
        if (!cancelled) setMessages(data.messages || [])
      } catch { if (!cancelled) setMessages([]) }
      finally { if (!cancelled) setChatLoading(false) }
    }
    setText('')
    loadMessages()
    return () => { cancelled = true }
  }, [selectedUser?.id, user?.id])

  async function loadUsers() {
    try {
      const response = await fetch(API_URL + '/api/users')
      if (!response.ok) return
      const data = await response.json()
      setUsers(data.filter((item) => item.id !== user?.id))
    } catch {}
  }

  async function submitLogin(credentials) {
    setNotice(''); setLoading(true)
    try {
      const response = await fetch(API_URL + '/api/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(credentials) })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'Sign in failed')
      setUser(data.user); navigate('/dashboard', true)
    } catch (error) { setNotice(error.message) }
    finally { setLoading(false) }
  }

  async function submitRegister(form) {
    setNotice(''); setLoading(true)
    try {
      const response = await fetch(API_URL + '/api/register', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form) })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'Registration failed')
      setUser(data.user); navigate('/dashboard', true)
    } catch (error) { setNotice(error.message) }
    finally { setLoading(false) }
  }

  function sendMessage(e) {
    e?.preventDefault()
    const trimmed = text.trim()
    if (!trimmed || !selectedUser || !socketRef.current?.connected) return
    socketRef.current.emit('private:message', { receiverId: selectedUser.id, text: trimmed }, (result) => {
      if (!result?.ok) setNotice(result?.error || 'Could not send message')
      else { setText(''); setNotice('') }
    })
  }

  function logout() {
    try { sessionStorage.removeItem('chatspace_user') } catch {}
    socketRef.current?.disconnect()
    setUser(null); setUsers([]); setMessages([]); setText(''); setSearch(''); setSocketConnected(false)
    navigate('/login', true)
  }

  const onlineCount = users.filter((item) => item.status === 'online').length

  if (!sessionReady) return <div className="boot-screen">Loading ChatSpace…</div>
  if (route.name === 'login') return <LoginPage loading={loading} notice={notice} onSubmit={submitLogin} onRegister={() => { setNotice(''); navigate('/register') }} />
  if (route.name === 'register') return <RegisterPage loading={loading} notice={notice} onSubmit={submitRegister} onLogin={() => { setNotice(''); navigate('/login') }} />
  if (route.name === 'dashboard') return <Dashboard user={user} users={users} search={search} setSearch={setSearch} onlineCount={onlineCount} openUser={(id) => navigate('/chat/' + encodeURIComponent(id))} socketConnected={socketConnected} onLogout={logout} />
  if (route.name === 'chat') return <ChatScreen user={user} selectedUser={selectedUser} messages={messages} text={text} setText={setText} notice={notice} chatLoading={chatLoading} socketConnected={socketConnected} sendMessage={sendMessage} onBack={() => navigate('/dashboard')} />
  return null
}

export default App
