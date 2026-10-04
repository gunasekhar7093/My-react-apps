import { useEffect, useRef } from 'react'

const Icon = ({ name, size = 20 }) => {
  const paths = {
    arrow: <><path d="M19 12H5" /><path d="m12 19-7-7 7-7" /></>,
    send: <><path d="m22 2-7 20-4-9-9-4Z" /><path d="M22 2 11 13" /></>,
  }
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>
}

export default function ChatScreen({ user, selectedUser, messages, text, setText, notice, chatLoading, socketConnected, sendMessage, onBack }) {
  const chatBodyRef = useRef(null)

  useEffect(() => {
    if (!chatBodyRef.current || chatLoading) return

    requestAnimationFrame(() => {
      const container = chatBodyRef.current
      if (container) {
        container.scrollTop = container.scrollHeight
      }
    })
  }, [messages, chatLoading, selectedUser?.id])

  if (!selectedUser) {
    return (
      <main className="app-screen">
        <header className="chat-header"><button className="back-button" onClick={onBack}><Icon name="arrow" size={21} /></button><strong>ChatSpace</strong></header>
        <div className="empty-chat"><strong>User not found</strong><button className="primary-button small" onClick={onBack}>Back to people</button></div>
      </main>
    )
  }

  return (
    <main className="app-screen chat-screen">
      <header className="chat-header">
        <button className="back-button" onClick={onBack} aria-label="Back to people"><Icon name="arrow" size={21} /></button>
        <span className="chat-avatar-wrap">
          <span className="large-avatar">{selectedUser.name?.charAt(0).toUpperCase()}</span>
          <i className={selectedUser.status === 'online' ? 'presence-dot online' : 'presence-dot'} />
        </span>
        <div className="chat-user">
          <strong>{selectedUser.name}</strong>
          <small className={selectedUser.status === 'online' ? 'status-online' : ''}>{selectedUser.status === 'online' ? 'Active now' : 'Offline'}</small>
        </div>
        <div className={socketConnected ? 'connection-status online chat-connection' : 'connection-status chat-connection'}><i />{socketConnected ? 'Connected' : 'Connecting'}</div>
      </header>

      <section className="chat-body" ref={chatBodyRef}>
        {notice && <div className="chat-notice">{notice}</div>}
        {chatLoading ? (
          <div className="empty-chat"><div className="chat-loading-dot" /><span>Loading conversation…</span></div>
        ) : messages.length === 0 ? (
          <div className="empty-chat">
            <span className="empty-chat-avatar">{selectedUser.name?.charAt(0).toUpperCase()}</span>
            <strong>Start a conversation with {selectedUser.name}</strong>
            <span>Send the first message below.</span>
          </div>
        ) : (
          <div className="messages">
            {messages.map((item) => (
              <div key={item.id} className={item.senderId === user.id ? 'message-line mine' : 'message-line'}>
                <div className="message">
                  <span>{item.text}</span>
                  <small>{new Date(item.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</small>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <form className="message-box" onSubmit={sendMessage}>
        <input value={text} onChange={(e) => setText(e.target.value)} placeholder={socketConnected ? 'Write a message…' : 'Connecting…'} disabled={!socketConnected} autoComplete="off" />
        <button type="submit" aria-label="Send message" disabled={!socketConnected || !text.trim()}><Icon name="send" size={19} /><span>Send</span></button>
      </form>
    </main>
  )
}
