export default function ChatScreen({ user, selectedUser, messages, text, setText, notice, chatLoading, socketConnected, sendMessage, onBack }) {
  if (!selectedUser) return <main className="app-screen"><header className="app-header"><button className="back-button" onClick={onBack}>←</button><strong>ChatSpace</strong></header><div className="empty-chat"><strong>User not found</strong><button className="primary-button small" onClick={onBack}>Back to people</button></div></main>

  return (
    <main className="app-screen chat-screen">
      <header className="chat-header">
        <button className="back-button" onClick={onBack} aria-label="Back to dashboard">←</button>
        <span className="large-avatar">{selectedUser.name?.charAt(0).toUpperCase()}</span>
        <div className="chat-user"><strong>{selectedUser.name}</strong><small className={selectedUser.status === 'online' ? 'status-online' : ''}>{selectedUser.status === 'online' ? 'Active now' : 'Offline'}</small></div>
        <div className={socketConnected ? 'connection-status online chat-connection' : 'connection-status chat-connection'}><i />{socketConnected ? 'Connected' : 'Connecting'}</div>
      </header>
      <section className="chat-body">
        {notice && <div className="chat-notice">{notice}</div>}
        {chatLoading ? <div className="empty-chat">Loading conversation…</div> : messages.length === 0 ? <div className="empty-chat"><span className="large-avatar">{selectedUser.name?.charAt(0).toUpperCase()}</span><strong>Start a conversation with {selectedUser.name}</strong><span>Send the first message below.</span></div> : <div className="messages">{messages.map((item) => <div key={item.id} className={item.senderId === user.id ? 'message-line mine' : 'message-line'}><div className="message"><span>{item.text}</span><small>{new Date(item.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</small></div></div>)}</div>}
      </section>
      <form className="message-box" onSubmit={sendMessage}><input value={text} onChange={(e) => setText(e.target.value)} placeholder={socketConnected ? 'Write a message…' : 'Connecting…'} disabled={!socketConnected} autoFocus /><button type="submit" disabled={!socketConnected || !text.trim()}>Send</button></form>
    </main>
  )
}
