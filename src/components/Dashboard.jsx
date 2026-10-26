import { useEffect, useState } from 'react'
import { getAvatarGradient } from '../utils/theme'

function formatLastSeen(lastSeenAt) {
  if (!lastSeenAt) return 'Offline'

  const date = new Date(lastSeenAt)
  if (Number.isNaN(date.getTime())) return 'Offline'

  const now = new Date()
  const isToday = date.toDateString() === now.toDateString()
  const yesterday = new Date(now)
  yesterday.setDate(now.getDate() - 1)
  const isYesterday = date.toDateString() === yesterday.toDateString()
  const time = date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })

  if (isToday) return 'Last seen today at ' + time
  if (isYesterday) return 'Last seen yesterday at ' + time

  return 'Last seen ' + date.toLocaleDateString('en-GB', { day: '2-digit', month: '2-digit', year: 'numeric' }) + ' at ' + time
}

const Icon = ({ name, size = 20 }) => {
  const paths = {
    search: <><circle cx="11" cy="11" r="7" /><path d="m20 20-4-4" /></>,
    users: <><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" /></>,
    arrow: <><path d="M5 12h14" /><path d="m13 6 6 6-6 6" /></>,
    logout: <><path d="M10 17l5-5-5-5" /><path d="M15 12H3" /><path d="M21 3v18" /></>,
    check: <polyline points="20 6 9 17 4 12" />,
  }
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>
}

export default function Dashboard({ user, users, search, setSearch, onlineCount, openUser, unreadCounts = {}, socketConnected, onLogout }) {
  const [showLogoutDialog, setShowLogoutDialog] = useState(false)
  const [activeFilter, setActiveFilter] = useState('all') // 'all' | 'online' | 'unread'

  useEffect(() => {
    if (!showLogoutDialog) return

    const onKeyDown = (event) => {
      if (event.key === 'Escape') setShowLogoutDialog(false)
    }

    document.body.style.overflow = 'hidden'
    window.addEventListener('keydown', onKeyDown)

    return () => {
      document.body.style.overflow = ''
      window.removeEventListener('keydown', onKeyDown)
    }
  }, [showLogoutDialog])

  const query = search.trim().toLowerCase()
  const sortedUsers = [...users].sort((a, b) => {
    const aTime = a.latestMessageAt ? new Date(a.latestMessageAt).getTime() : 0
    const bTime = b.latestMessageAt ? new Date(b.latestMessageAt).getTime() : 0

    if (bTime !== aTime) return bTime - aTime
    return a.name.localeCompare(b.name)
  })

  const unreadUsersCount = users.filter((u) => (unreadCounts[u.id] || 0) > 0).length

  const filteredUsers = sortedUsers.filter((item) => {
    // 1. Search text filter
    if (query) {
      const matches = item.name.toLowerCase().includes(query) || item.username.toLowerCase().includes(query)
      if (!matches) return false
    }

    // 2. Tab chips filter
    if (activeFilter === 'online') return item.status === 'online'
    if (activeFilter === 'unread') return (unreadCounts[item.id] || 0) > 0
    return true
  })

  return (
    <main className="app-screen dashboard-screen">
      <header className="app-header">
        <div className="header-brand">
          <div className="brand-mark">C</div>
          <div><strong>ChatSpace</strong><span>Private conversations</span></div>
        </div>
        <div className="header-actions">
          <div className={socketConnected ? 'connection-status online' : 'connection-status'}><i />{socketConnected ? 'Connected' : 'Connecting'}</div>
          <div className="current-user">
            <span
              className="user-avatar"
              style={{ background: getAvatarGradient(user.id || user.name) }}
            >
              {user.name?.charAt(0).toUpperCase()}
            </span>
            <span>{user.name}</span>
          </div>
          <button className="header-button" onClick={() => setShowLogoutDialog(true)}><Icon name="logout" size={17} /><span>Log out</span></button>
        </div>
      </header>

      <section className="dashboard-page">
        <div className="dashboard-hero">
          <div>
            <span className="eyebrow">YOUR SPACE</span>
            <h1>People</h1>
            <p>Choose someone to start a private conversation.</p>
          </div>
          <div className="dashboard-stats">
            <div><strong>{users.length}</strong><span>People</span></div>
            <div><strong>{onlineCount}</strong><span>Online</span></div>
          </div>
        </div>

        <div className="dashboard-toolbar-group">
          <div className="dashboard-toolbar">
            <div className="dashboard-search">
              <Icon name="search" size={20} />
              <input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search people by name or email…"
                aria-label="Search people"
              />
              {search && <button className="search-clear" onClick={() => setSearch('')} aria-label="Clear search">×</button>}
            </div>
            <span className="result-count">{filteredUsers.length} {filteredUsers.length === 1 ? 'person' : 'people'}</span>
          </div>

          {/* Filter Chips matching mobile app */}
          <div className="dashboard-filter-chips">
            <button
              type="button"
              className={`filter-chip ${activeFilter === 'all' ? 'active' : ''}`}
              onClick={() => setActiveFilter('all')}
            >
              <span>All</span>
              <span className="chip-badge">{users.length}</span>
            </button>

            <button
              type="button"
              className={`filter-chip ${activeFilter === 'online' ? 'active' : ''}`}
              onClick={() => setActiveFilter('online')}
            >
              <i className="chip-dot online" />
              <span>Online</span>
              <span className="chip-badge">{onlineCount}</span>
            </button>

            <button
              type="button"
              className={`filter-chip ${activeFilter === 'unread' ? 'active' : ''}`}
              onClick={() => setActiveFilter('unread')}
            >
              <span>Unread</span>
              {unreadUsersCount > 0 && <span className="chip-badge unread">{unreadUsersCount}</span>}
            </button>
          </div>
        </div>

        <div className="user-grid">
          {filteredUsers.map((item) => (
            <button className="user-card" key={item.id} onClick={() => openUser(item.id)}>
              <span className="user-card-avatar">
                <span
                  className="large-avatar"
                  style={{ background: getAvatarGradient(item.id || item.name) }}
                >
                  {item.name?.charAt(0).toUpperCase()}
                </span>
                <i className={item.status === 'online' ? 'presence-dot online' : 'presence-dot'} />
              </span>
              <span className="user-card-info">
                <strong>{item.name}</strong>
                <small className={item.status === 'online' ? 'status-online' : ''}>
                  {item.status === 'online' ? 'Available now' : formatLastSeen(item.lastSeenAt)}
                </small>
              </span>
              <span className="user-card-actions">
                {unreadCounts[item.id] > 0 && (
                  <span className="unread-badge">
                    {unreadCounts[item.id] > 99 ? '99+' : unreadCounts[item.id]}
                  </span>
                )}
                <span className="user-arrow"><Icon name="arrow" size={19} /></span>
              </span>
            </button>
          ))}
          {!filteredUsers.length && (
            <div className="empty-state">
              <div className="empty-icon"><Icon name="users" size={24} /></div>
              <strong>
                {query
                  ? 'No people found'
                  : activeFilter === 'online'
                  ? 'No one is online right now'
                  : activeFilter === 'unread'
                  ? 'No unread messages'
                  : users.length
                  ? 'No people found'
                  : 'Your people list is empty'}
              </strong>
              <span>
                {query
                  ? 'Try another name or email address.'
                  : activeFilter === 'online'
                  ? 'Check back later or message anyone to reach them.'
                  : activeFilter === 'unread'
                  ? "You're all caught up with your conversations!"
                  : users.length
                  ? 'Try clearing the search or filter.'
                  : 'Create another account to start chatting.'}
              </span>
            </div>
          )}
        </div>
      </section>

      {showLogoutDialog && (
        <div
          className="dialog-backdrop"
          role="presentation"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setShowLogoutDialog(false)
          }}
        >
          <section
            className="logout-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="logout-dialog-title"
            aria-describedby="logout-dialog-description"
          >
            <div className="logout-dialog-icon">
              <Icon name="logout" size={22} />
            </div>
            <h2 id="logout-dialog-title">Log out of ChatSpace?</h2>
            <p id="logout-dialog-description">
              You will be signed out of this account on this device.
            </p>
            <div className="logout-dialog-actions">
              <button
                type="button"
                className="dialog-cancel"
                onClick={() => setShowLogoutDialog(false)}
              >
                Cancel
              </button>
              <button
                type="button"
                className="dialog-confirm"
                onClick={() => {
                  setShowLogoutDialog(false)
                  onLogout()
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
