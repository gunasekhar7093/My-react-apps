import React from 'react'

export default function ChatScreen({
  user,
  selectedUser,
  messages,
  text,
  setText,
  notice,
  chatLoading,
  socketConnected,
  hasMoreMessages,
  loadingOlder,
  handleMessagesScroll,
  sendMessage,
  inputRef,
  bottomRef,
  setMobileUsersOpen,
  Avatar,
  Icon,
}) {
  return (
          <section className="conversation">
            {selectedUser ? (
              <>
                <header className="conversation-header">
                  <button className="mobile-menu-button" onClick={() => setMobileUsersOpen(true)} aria-label="Open people">
                    <Icon name="menu" />
                  </button>
                  <Avatar name={selectedUser.name} size="lg" online={selectedUser.status === 'online'} />
                  <div className="conversation-person">
                    <h2>{selectedUser.name}</h2>
                    <span className={selectedUser.status === 'online' ? 'presence online' : 'presence'}>
                      {selectedUser.status === 'online' ? 'Active now' : 'Offline'}
                    </span>
                  </div>
                </header>

                <div className="messages-area" onScroll={handleMessagesScroll}>
                  {loadingOlder && <div className="older-loader"><span className="spinner" /> Loading older messages…</div>}
                  {chatLoading ? (
                    <div className="chat-state"><span className="spinner" /> Loading conversation…</div>
                  ) : messages.length === 0 ? (
                    <div className="welcome-chat">
                      <Avatar name={selectedUser.name} size="xl" online={selectedUser.status === 'online'} />
                      <span className="eyebrow">PRIVATE CONVERSATION</span>
                      <h3>Say hello to {selectedUser.name.split(' ')[0]}</h3>
                      <p>Messages you send here are visible only to you and {selectedUser.name}.</p>
                    </div>
                  ) : (
                    <>
                      <div className="day-divider"><span>Conversation</span></div>
                      {messages.map((item) => (
                        <div key={item.id} className={item.senderId === user.id ? 'message-row mine' : 'message-row'}>
                          <div className="message-bubble">
                            <span>{item.text}</span>
                            <small>{new Date(item.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</small>
                          </div>
                        </div>
                      ))}
                    </>
                  )}
                  <div ref={bottomRef} />
                </div>

                {notice && <div className="chat-notice">{notice}</div>}

                <form className="message-form" onSubmit={sendMessage}>
                  <div className="composer">
                    <input
                      ref={inputRef}
                      value={text}
                      onChange={(e) => setText(e.target.value)}
                      placeholder={socketConnected ? 'Write a message…' : 'Connecting to ChatSpace…'}
                      maxLength={2000}
                      disabled={!socketConnected}
                      aria-label="Message"
                    />
                    <button className="send-button" type="submit" disabled={!socketConnected || !text.trim()} aria-label="Send message">
                      <Icon name="send" />
                    </button>
                  </div>
                  <span className="composer-hint">Enter to send · Messages are private</span>
                </form>
              </>
            ) : (
              <div className="no-chat">
                <button className="mobile-menu-button mobile-only-menu" onClick={() => setMobileUsersOpen(true)} aria-label="Open people">
                  <Icon name="menu" />
                </button>
                <div className="no-chat-icon"><Icon name="message" /></div>
                <span className="eyebrow">YOUR PRIVATE SPACE</span>
                <h2>Choose someone to start chatting</h2>
                <p>Select a person from the left to open a private conversation.</p>
                <button className="primary-action" onClick={() => setMobileUsersOpen(true)}>Browse people</button>
              </div>
            )}
          </section>
  )
}
