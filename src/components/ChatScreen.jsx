export default function ChatScreen({ user, selectedUser, messages, text, setText, notice, chatLoading, socketConnected, loadingOlder, handleMessagesScroll, sendMessage, inputRef, bottomRef, goBack, Avatar, Icon }) {
  if (!selectedUser) {
    return <main className="chat-screen"><div className="chat-loading">Loading conversation…</div></main>
  }

  return (
    <main className="chat-screen">
      <header className="chat-header">
        <button className="back-button" onClick={goBack} aria-label="Back to dashboard"><Icon name="back" /></button>
        <Avatar name={selectedUser.name} size="lg" online={selectedUser.status === 'online'} />
        <div className="chat-person"><strong>{selectedUser.name}</strong><span>{selectedUser.status === 'online' ? 'Active now' : 'Offline'}</span></div>
      </header>

      <div className="chat-body" onScroll={handleMessagesScroll}>
        {loadingOlder && <div className="older-loader"><span className="spinner" /> Loading older messages…</div>}
        {chatLoading ? <div className="chat-state"><span className="spinner" /> Loading conversation…</div> : messages.length === 0 ? (
          <div className="welcome-chat">
            <Avatar name={selectedUser.name} size="xl" online={selectedUser.status === 'online'} />
            <span className="eyebrow">PRIVATE CONVERSATION</span>
            <h2>Say hello to {selectedUser.name.split(' ')[0]}</h2>
            <p>Messages you send here are visible only to you and {selectedUser.name}.</p>
          </div>
        ) : (
          <div className="message-list">
            {messages.map((item) => (
              <div key={item.id} className={item.senderId === user.id ? 'message-row mine' : 'message-row'}>
                <div className="message-bubble"><span>{item.text}</span><small>{new Date(item.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</small></div>
              </div>
            ))}
            <div ref={bottomRef} />
          </div>
        )}
      </div>

      {notice && <div className="chat-notice">{notice}</div>}

      <form className="chat-composer" onSubmit={sendMessage}>
        <input ref={inputRef} value={text} onChange={(e) => setText(e.target.value)} placeholder={socketConnected ? 'Write a message…' : 'Connecting to ChatSpace…'} maxLength={2000} disabled={!socketConnected} />
        <button className="send-button" type="submit" disabled={!socketConnected || !text.trim()} aria-label="Send message"><Icon name="send" /></button>
      </form>
    </main>
  )
}
