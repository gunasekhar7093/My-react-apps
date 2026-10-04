import { useMemo } from 'react'

export default function Dashboard({
  users,
  selectedUser,
  search,
  setSearch,
  onlineCount,
  openUser,
  loadUsers,
  mobileUsersOpen,
  setMobileUsersOpen,
  Avatar,
  Icon,
}) {
  const filteredUsers = useMemo(() => {
    const query = search.trim().toLowerCase()
    if (!query) return users
    return users.filter((item) => item.name.toLowerCase().includes(query) || item.username.toLowerCase().includes(query))
  }, [users, search])
  return (
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
  )
}
