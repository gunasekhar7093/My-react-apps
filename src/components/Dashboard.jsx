export default function Dashboard({ user, users, search, setSearch, onlineCount, openUser, socketConnected, onLogout }) {
  const query = search.trim().toLowerCase()
  const filteredUsers = query ? users.filter((item) => item.name.toLowerCase().includes(query) || item.username.toLowerCase().includes(query)) : users

  return (
    <main className="app-screen">
      <header className="app-header">
        <div className="header-brand"><div className="brand-mark">◌</div><div><strong>ChatSpace</strong><span>Private conversations</span></div></div>
        <div className="header-actions">
          <div className={socketConnected ? 'connection-status online' : 'connection-status'}><i />{socketConnected ? 'Connected' : 'Connecting'}</div>
          <div className="current-user"><span className="user-avatar">{user.name?.charAt(0).toUpperCase()}</span><span>{user.name}</span></div>
          <button className="header-button" onClick={onLogout}>Log out</button>
        </div>
      </header>
      <section className="dashboard-page">
        <div className="dashboard-title"><div><span className="eyebrow">YOUR PEOPLE</span><h1>People</h1><p>{users.length} {users.length === 1 ? 'person' : 'people'} · {onlineCount} online</p></div><div className="dashboard-search"><span>⌕</span><input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search people" /></div></div>
        <div className="user-grid">
          {filteredUsers.map((item) => <button className="user-card" key={item.id} onClick={() => openUser(item.id)}><span className="large-avatar">{item.name?.charAt(0).toUpperCase()}</span><span className="user-card-info"><strong>{item.name}</strong><small className={item.status === 'online' ? 'status-online' : ''}>{item.status === 'online' ? 'Online now' : 'Offline'}</small></span><span className="user-arrow">→</span></button>)}
          {!filteredUsers.length && <div className="empty-state"><strong>{users.length ? 'No people found' : 'No other users yet'}</strong><span>{users.length ? 'Try a different search.' : 'Create another account to start chatting.'}</span></div>}
        </div>
      </section>
    </main>
  )
}
