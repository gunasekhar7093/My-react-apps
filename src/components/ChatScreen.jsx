import { useEffect, useRef, useState } from 'react'

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
    arrow: <><path d="M19 12H5" /><path d="m12 19-7-7 7-7" /></>,
    send: <><path d="m22 2-7 20-4-9-9-4Z" /><path d="M22 2 11 13" /></>,
    clip: <path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l7.88-7.88" />,
    close: <><path d="M18 6 6 18" /><path d="m6 6 12 12" /></>,
    video: <><path d="m22 8-6 4 6 4V8Z" /><rect width="14" height="12" x="2" y="6" rx="2" ry="2" /></>,
    download: <><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" /><polyline points="7 10 12 15 17 10" /><line x1="12" y1="15" x2="12" y2="3" /></>,
  }
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>
}

export default function ChatScreen({
  user,
  selectedUser,
  messages,
  text,
  setText,
  notice,
  chatLoading,
  socketConnected,
  sendMessage,
  sendMedia,
  apiUrl = '',
  token = '',
  onBack,
}) {
  const chatBodyRef = useRef(null)
  const fileInputRef = useRef(null)
  const knownMessageIdsRef = useRef(new Set())
  const initializedMessagesRef = useRef(false)
  const previousMessageCountRef = useRef(0)
  const initialScrollRef = useRef(true)
  const isNearBottomRef = useRef(true)

  const [animatedMessageIds, setAnimatedMessageIds] = useState(new Set())
  const [selectedFile, setSelectedFile] = useState(null)
  const [filePreview, setFilePreview] = useState(null)
  const [uploading, setUploading] = useState(false)
  const [activeMediaModal, setActiveMediaModal] = useState(null)
  const [downloading, setDownloading] = useState(false)

  function getMediaSrc(mediaUrl) {
    if (!mediaUrl) return null
    const base = mediaUrl.startsWith('http') ? mediaUrl : (apiUrl + mediaUrl)
    if (!token || base.includes('token=')) return base
    const sep = base.includes('?') ? '&' : '?'
    return `${base}${sep}token=${encodeURIComponent(token)}`
  }

  useEffect(() => {
    if (!activeMediaModal) return
    const onKeyDown = (e) => {
      if (e.key === 'Escape') setActiveMediaModal(null)
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [activeMediaModal])

  async function downloadActiveMedia() {
    if (!activeMediaModal?.url || downloading) return
    setDownloading(true)
    try {
      const response = await fetch(activeMediaModal.url)
      if (!response.ok) throw new Error('Download failed')
      const blob = await response.blob()
      const blobUrl = window.URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = blobUrl
      link.download = activeMediaModal.name || 'chat-media'
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)
      window.URL.revokeObjectURL(blobUrl)
    } catch {
      const link = document.createElement('a')
      link.href = activeMediaModal.url
      link.download = activeMediaModal.name || 'chat-media'
      link.target = '_blank'
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)
    } finally {
      setDownloading(false)
    }
  }

  useEffect(() => {
    if (chatLoading) return

    const currentIds = new Set(messages.map((item) => item.id))

    if (!initializedMessagesRef.current) {
      knownMessageIdsRef.current = currentIds
      initializedMessagesRef.current = true
      return
    }

    const newIds = [...currentIds].filter((id) => !knownMessageIdsRef.current.has(id))

    if (newIds.length) {
      setAnimatedMessageIds((current) => {
        const next = new Set(current)
        newIds.forEach((id) => next.add(id))
        return next
      })

      window.setTimeout(() => {
        setAnimatedMessageIds((current) => {
          const next = new Set(current)
          newIds.forEach((id) => next.delete(id))
          return next
        })
      }, 320)
    }

    knownMessageIdsRef.current = currentIds
  }, [messages, chatLoading, selectedUser?.id])

  useEffect(() => {
    knownMessageIdsRef.current = new Set()
    initializedMessagesRef.current = false
    previousMessageCountRef.current = 0
    initialScrollRef.current = true
    isNearBottomRef.current = true
    setAnimatedMessageIds(new Set())
    setSelectedFile(null)
    setFilePreview(null)
  }, [selectedUser?.id])

  const handleScroll = () => {
    const container = chatBodyRef.current
    if (!container) return
    const distanceFromBottom = container.scrollHeight - container.scrollTop - container.clientHeight
    isNearBottomRef.current = distanceFromBottom < 120
  }

  useEffect(() => {
    if (!chatBodyRef.current || chatLoading) return

    const container = chatBodyRef.current

    // Case 1: Initial conversation open / first load with messages
    if (initialScrollRef.current) {
      if (messages.length > 0) {
        requestAnimationFrame(() => {
          if (!container) return
          container.scrollTop = container.scrollHeight
          initialScrollRef.current = false
          previousMessageCountRef.current = messages.length
          isNearBottomRef.current = true
        })
      }
      return
    }

    const previousCount = previousMessageCountRef.current
    const currentCount = messages.length

    // Always update recorded message count
    previousMessageCountRef.current = currentCount

    // If message count did not increase (e.g. background sync or re-render), never auto-scroll
    if (currentCount <= previousCount) {
      return
    }

    // Case 2: New message(s) arrived
    const latestMessage = messages[messages.length - 1]
    const isSentByMe = latestMessage?.senderId === user?.id

    // Only scroll to bottom if the current user sent the message or was already near the bottom
    if (isSentByMe || isNearBottomRef.current) {
      requestAnimationFrame(() => {
        if (!container) return
        container.scrollTo({
          top: container.scrollHeight,
          behavior: 'smooth',
        })
        isNearBottomRef.current = true
      })
    }
  }, [messages, chatLoading, selectedUser?.id, user?.id])

  function handleFileSelect(e) {
    const file = e.target.files?.[0]
    if (!file) return

    setSelectedFile(file)
    if (file.type.startsWith('image/')) {
      const reader = new FileReader()
      reader.onload = (event) => setFilePreview(event.target.result)
      reader.readAsDataURL(file)
    } else {
      setFilePreview(null)
    }
  }

  function clearSelectedFile() {
    setSelectedFile(null)
    setFilePreview(null)
    if (fileInputRef.current) fileInputRef.current.value = ''
  }

  async function handleFormSubmit(e) {
    e.preventDefault()

    if (selectedFile) {
      if (uploading) return
      setUploading(true)
      try {
        await sendMedia({ file: selectedFile, caption: text })
        clearSelectedFile()
        setText('')
      } catch {
        // notice is handled by App.jsx
      } finally {
        setUploading(false)
      }
    } else {
      sendMessage(e)
    }
  }

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
          <small className={selectedUser.status === 'online' ? 'status-online' : ''}>{selectedUser.status === 'online' ? 'Active now' : formatLastSeen(selectedUser.lastSeenAt)}</small>
        </div>
        <div className={socketConnected ? 'connection-status online chat-connection' : 'connection-status chat-connection'}><i />{socketConnected ? 'Connected' : 'Connecting'}</div>
      </header>

      <section className="chat-body" ref={chatBodyRef} onScroll={handleScroll}>
        {notice && <div className="chat-notice">{notice}</div>}
        {chatLoading ? (
          <div className="empty-chat"><div className="chat-loading-dot" /><span>Loading conversation…</span></div>
        ) : messages.length === 0 ? (
          <div className="empty-chat">
            <span className="empty-chat-avatar">{selectedUser.name?.charAt(0).toUpperCase()}</span>
            <strong>Start a conversation with {selectedUser.name}</strong>
            <span>Send the first message or photo below.</span>
          </div>
        ) : (
          <div className="messages">
            {messages.map((item, index) => {
              const itemDate = new Date(item.createdAt)
              const previousDate = index > 0 ? new Date(messages[index - 1].createdAt) : null
              const isNewDate = !previousDate || itemDate.toDateString() !== previousDate.toDateString()
              const mediaSrc = getMediaSrc(item.mediaUrl)

              return (
                <div key={item.id}>
                  {isNewDate && (
                    <div className="chat-date-divider">
                      <span>{itemDate.toLocaleDateString('en-GB', { day: '2-digit', month: '2-digit', year: 'numeric' })}</span>
                    </div>
                  )}
                  <div className={item.senderId === user.id ? 'message-line mine' : 'message-line'}>
                    <div className={animatedMessageIds.has(item.id) ? 'message message-new' : 'message'}>
                      {mediaSrc && (
                        <div className="message-media-wrap">
                          {item.mediaType === 'video' ? (
                            <video
                              src={mediaSrc}
                              controls
                              playsInline
                              preload="metadata"
                              className="chat-media-video"
                            />
                          ) : (
                            <img
                              src={mediaSrc}
                              alt={item.mediaName || 'Media'}
                              className="chat-media-image"
                              loading="lazy"
                              onClick={() =>
                                setActiveMediaModal({
                                  url: mediaSrc,
                                  name: item.mediaName || 'Photo',
                                  type: item.mediaType || 'image',
                                  caption: item.text || '',
                                  date: itemDate,
                                  senderName: item.senderId === user.id ? 'You' : selectedUser.name,
                                  avatar: (item.senderId === user.id ? user.name : selectedUser.name)?.charAt(0)?.toUpperCase() || '?',
                                })
                              }
                            />
                          )}
                        </div>
                      )}
                      {item.text && <span>{item.text}</span>}
                      <small className="message-meta">
                        <span>{itemDate.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })}</span>
                        {item.senderId === user.id && (
                          <span
                            className={`msg-status-ticks ${item.readAt ? 'read' : item.deliveredAt ? 'delivered' : 'sent'}`}
                            title={item.readAt ? 'Read (Two White Ticks)' : item.deliveredAt ? 'Delivered (Two Gray Ticks)' : 'Sent (One Gray Tick)'}
                          >
                            {item.readAt || item.deliveredAt ? '✓✓' : '✓'}
                          </span>
                        )}
                      </small>
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </section>

      {/* Selected media file preview banner */}
      {selectedFile && (
        <div className="media-preview-bar">
          {filePreview ? (
            <img src={filePreview} alt="Preview" className="media-preview-thumb" />
          ) : (
            <div className="media-preview-icon"><Icon name="video" size={24} /></div>
          )}
          <div className="media-preview-info">
            <strong>{selectedFile.name}</strong>
            <small>{(selectedFile.size / (1024 * 1024)).toFixed(1)} MB</small>
          </div>
          <button type="button" className="media-preview-clear" onClick={clearSelectedFile} aria-label="Remove attached file">
            <Icon name="close" size={16} />
          </button>
        </div>
      )}

      <form className="message-box" onSubmit={handleFormSubmit}>
        <input
          type="file"
          ref={fileInputRef}
          accept="image/*,video/*"
          style={{ display: 'none' }}
          onChange={handleFileSelect}
        />
        <button
          type="button"
          className="attachment-button"
          onClick={() => fileInputRef.current?.click()}
          disabled={!socketConnected || uploading}
          aria-label="Attach photo or video"
          title="Share photo or video"
        >
          <Icon name="clip" size={20} />
        </button>

        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder={selectedFile ? 'Add a caption…' : 'Write a message…'}
          disabled={!socketConnected || uploading}
          autoComplete="off"
        />

        <button
          type="submit"
          aria-label="Send message"
          disabled={!socketConnected || (!text.trim() && !selectedFile) || uploading}
          onMouseDown={(event) => event.preventDefault()}
        >
          {uploading ? (
            <span>Uploading…</span>
          ) : (
            <>
              <Icon name="send" size={19} />
              <span>Send</span>
            </>
          )}
        </button>
      </form>

      {/* Instagram-style In-App Photo & Video Preview */}
      {activeMediaModal && (
        <div
          className="insta-preview-overlay"
          onClick={() => setActiveMediaModal(null)}
          role="dialog"
          aria-modal="true"
        >
          {/* Top Bar with Sender Info and Close Button */}
          <div className="insta-preview-topbar" onClick={(e) => e.stopPropagation()}>
            <div className="insta-preview-user">
              <span className="insta-preview-avatar">{activeMediaModal.avatar}</span>
              <div className="insta-preview-meta">
                <span className="insta-preview-name">{activeMediaModal.senderName}</span>
                <span className="insta-preview-time">
                  {activeMediaModal.date.toLocaleDateString('en-GB', { day: '2-digit', month: 'short' })} • {activeMediaModal.date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })}
                </span>
              </div>
            </div>

            <div className="insta-preview-actions">
              <button
                type="button"
                className="insta-preview-btn"
                onClick={downloadActiveMedia}
                disabled={downloading}
                title="Download media"
                aria-label="Download media"
              >
                <Icon name="download" size={20} />
              </button>

              <button
                type="button"
                className="insta-preview-close"
                onClick={() => setActiveMediaModal(null)}
                title="Close (Esc)"
                aria-label="Close"
              >
                <Icon name="close" size={22} />
              </button>
            </div>
          </div>

          {/* Centered Media Content */}
          <div className="insta-preview-stage" onClick={() => setActiveMediaModal(null)}>
            <div className="insta-preview-media-container" onClick={(e) => e.stopPropagation()}>
              {activeMediaModal.type === 'video' ? (
                <video
                  src={activeMediaModal.url}
                  controls
                  autoPlay
                  playsInline
                  className="insta-preview-element"
                />
              ) : (
                <img
                  src={activeMediaModal.url}
                  alt={activeMediaModal.name}
                  className="insta-preview-element"
                />
              )}

              {activeMediaModal.caption && (
                <div className="insta-preview-caption-bar">
                  <span className="insta-preview-caption-text">{activeMediaModal.caption}</span>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </main>
  )
}
