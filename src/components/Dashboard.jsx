export default function Dashboard({ user, users, search, setSearch, onlineCount, openUser, loadUsers, logout, Avatar, Icon }) {
  const query = search.trim().toLowerCase()
  const filteredUsers = !query ? users : users.filter((item) =>
    item.name.toLowerCase().includes(query) || item.username.toLowerCase().includes(query)
  )

  return (
    <main className="dashboard-screen">
      <header className="dashboard-header">
        <div className="dashboard-brand">
          <div className="brand-mark"><Icon name="message" /></div>
          <div><strong>ChatSpace</strong><span>Private conversations</span></div>
        </div>
        <div className="dashboard-account">
          <Avatar name={user.name} size="sm" online />
          <span>{user.name}</span>
          <button className="logout-button" onClick={logout} title="Log out"><Icon name="logout" /></button>
        </div>
      </header>

      <section className="dashboard-content">
        <div className="dashboard-title-row">
          <div>
            <span className="eyebrow">YOUR CONNECTIONS</span>
            <h1>People</h1>
            <p>{users.length} {users.length === 1 ? 'person' : 'people'} · {onlineCount} online</p>
          </div>
          <button className="refresh-button" onClick={loadUsers}><Icon name="refresh" /> Refresh</button>
        </div>

        <div className="dashboard-search">
          <Icon name="search" />
          <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search people by name or email" />
          {search && <button onClick={() => setSearch('')} aria-label="Clear search"><Icon name="close" /></button>}
        </div>

        <div className="dashboard-list">
          {filteredUsers.map((item) => (
            <button className="dashboard-user" key={item.id} onClick={() => openUser(item)}>
              <Avatar name={item.name} size="lg" online={item.status === 'online'} />
              <span className="dashboard-user-copy">
                <strong>{item.name}</strong>
                <small>{item.status === 'online' ? 'Online now' : 'Offline'} · {item.username}</small>
              </span>
              <span className="dashboard-arrow">›</span>
            </button>
          ))}
          {filteredUsers.length === 0 && (
            <div className="dashboard-empty">
              <Icon name="search" />
              <strong>{users.length ? 'No people found' : 'No other people yet'}</strong>
              <span>{users.length ? 'Try another search.' : 'Create another account to start chatting.'}</span>
            </div>
          )}
        </div>
      </section>
    </main>
  )
}
