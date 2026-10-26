import { useEffect, useRef, useState } from 'react'
import { getAvatarGradient, formatDateBadge, formatBytes } from '../utils/theme'

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
    photo: <><rect width="18" height="18" x="3" y="3" rx="2" ry="2" /><circle cx="9" cy="9" r="2" /><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21" /></>,
    camera: <><path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z" /><circle cx="12" cy="13" r="3" /></>,
    download: <><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" /><polyline points="7 10 12 15 17 10" /><line x1="12" y1="15" x2="12" y2="3" /></>,
    trash: <><path d="M3 6h18" /><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6" /><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2" /><line x1="10" y1="11" x2="10" y2="17" /><line x1="14" y1="11" x2="14" y2="17" /></>,
    reply: <><polyline points="9 17 4 12 9 7" /><path d="M20 18v-2a4 4 0 0 0-4-4H4" /></>,
    copy: <><rect width="14" height="14" x="8" y="8" rx="2" ry="2" /><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2" /></>,
    check: <polyline points="20 6 9 17 4 12" />,
    chevronDown: <polyline points="6 9 12 15 18 9" />,
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
  unsendMessage,
  hasMoreOlder = false,
  loadingOlder = false,
  loadOlderMessages,
  apiUrl = '',
  token = '',
  onBack,
}) {
  const chatBodyRef = useRef(null)
  const fileInputRef = useRef(null)
  const cameraInputRef = useRef(null)
  const textInputRef = useRef(null)
  const messageRefs = useRef({})
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

  // Reply & quoting state matching mobile
  const [replyToMessage, setReplyToMessage] = useState(null)
  const [highlightedMessageId, setHighlightedMessageId] = useState(null)
  const highlightTimeoutRef = useRef(null)
  const sendingRef = useRef(false)
  const [sending, setSending] = useState(false)

  // Message action state & unsend confirmation modal
  const [unsendTargetMessage, setUnsendTargetMessage] = useState(null)
  const [copyFeedbackId, setCopyFeedbackId] = useState(null)

  // Floating scroll-to-bottom and new message indicator
  const [showScrollBottom, setShowScrollBottom] = useState(false)
  const [hasNewScrolledMessages, setHasNewScrolledMessages] = useState(false)

  // Attachment popup menu and drag-and-drop
  const [showAttachmentMenu, setShowAttachmentMenu] = useState(false)
  const [isDragOver, setIsDragOver] = useState(false)

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

  // Global escape to cancel reply or close modals
  useEffect(() => {
    const onKeyDown = (e) => {
      if (e.key === 'Escape') {
        if (showAttachmentMenu) setShowAttachmentMenu(false)
        else if (replyToMessage) setReplyToMessage(null)
        else if (unsendTargetMessage) setUnsendTargetMessage(null)
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [showAttachmentMenu, replyToMessage, unsendTargetMessage])

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

  // Animate newly arriving messages
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

  // Clear highlight timer on unmount
  useEffect(() => {
    return () => {
      if (highlightTimeoutRef.current) {
        clearTimeout(highlightTimeoutRef.current)
        highlightTimeoutRef.current = null
      }
    }
  }, [])

  // Reset when conversation changes
  useEffect(() => {
    if (highlightTimeoutRef.current) {
      clearTimeout(highlightTimeoutRef.current)
      highlightTimeoutRef.current = null
    }
    knownMessageIdsRef.current = new Set()
    initializedMessagesRef.current = false
    previousMessageCountRef.current = 0
    initialScrollRef.current = true
    isNearBottomRef.current = true
    setShowScrollBottom(false)
    setHasNewScrolledMessages(false)
    setAnimatedMessageIds(new Set())
    setSelectedFile(null)
    setFilePreview(null)
    setReplyToMessage(null)
    setHighlightedMessageId(null)
    sendingRef.current = false
    setSending(false)
    setShowAttachmentMenu(false)
  }, [selectedUser?.id])

  const handleScroll = () => {
    const container = chatBodyRef.current
    if (!container) return
    const distanceFromBottom = container.scrollHeight - container.scrollTop - container.clientHeight
    const nearBottom = distanceFromBottom < 140
    isNearBottomRef.current = nearBottom
    setShowScrollBottom(!nearBottom)

    if (nearBottom) {
      setHasNewScrolledMessages(false)
    }

    // Infinite scroll: load older messages when reaching near top
    if (container.scrollTop < 40 && hasMoreOlder && !loadingOlder && loadOlderMessages) {
      const prevScrollHeight = container.scrollHeight
      loadOlderMessages().then(() => {
        // Maintain scroll position after prepending older messages
        requestAnimationFrame(() => {
          if (container) {
            const heightDiff = container.scrollHeight - prevScrollHeight
            container.scrollTop += heightDiff
          }
        })
      })
    }
  }

  const scrollToBottom = (smooth = true) => {
    const container = chatBodyRef.current
    if (!container) return
    if (smooth) {
      container.scrollTo({ top: container.scrollHeight, behavior: 'smooth' })
    } else {
      container.scrollTop = container.scrollHeight
    }
    setHasNewScrolledMessages(false)
  }

  // Scroll to bottom when messages update
  useEffect(() => {
    if (!chatBodyRef.current || chatLoading) return
    const container = chatBodyRef.current

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
    previousMessageCountRef.current = currentCount

    if (currentCount <= previousCount) return

    const latestMessage = messages[messages.length - 1]
    const isSentByMe = latestMessage?.senderId === user?.id

    if (isSentByMe || isNearBottomRef.current) {
      requestAnimationFrame(() => {
        if (!container) return
        container.scrollTo({ top: container.scrollHeight, behavior: 'smooth' })
        isNearBottomRef.current = true
      })
    } else {
      setHasNewScrolledMessages(true)
    }
  }, [messages, chatLoading, selectedUser?.id, user?.id])

  // Smooth scroll to quoted target message and highlight it
  function handleQuotedMessageClick(quotedId) {
    if (!quotedId) return
    const idStr = String(quotedId).trim()
    if (!idStr) return

    const targetEl = messageRefs.current[idStr]
    if (targetEl) {
      targetEl.scrollIntoView({ behavior: 'smooth', block: 'center' })

      if (highlightTimeoutRef.current) {
        clearTimeout(highlightTimeoutRef.current)
      }

      setHighlightedMessageId(idStr)
      highlightTimeoutRef.current = window.setTimeout(() => {
        setHighlightedMessageId(null)
        highlightTimeoutRef.current = null
      }, 1500)
    }
  }

  function handleFileSelect(e) {
    const file = e.target.files?.[0]
    if (!file) return
    processSelectedFile(file)
  }

  function processSelectedFile(file) {
    setSelectedFile(file)
    setShowAttachmentMenu(false)
    if (file.type.startsWith('image/')) {
      const reader = new FileReader()
      reader.onload = (event) => setFilePreview(event.target.result)
      reader.readAsDataURL(file)
    } else {
      setFilePreview(null)
    }
    // Focus text input for caption
    window.setTimeout(() => textInputRef.current?.focus(), 100)
  }

  function clearSelectedFile() {
    setSelectedFile(null)
    setFilePreview(null)
    if (fileInputRef.current) fileInputRef.current.value = ''
    if (cameraInputRef.current) cameraInputRef.current.value = ''
  }

  // Clipboard paste support (Ctrl+V) for images/screenshots
  useEffect(() => {
    function handlePaste(e) {
      const items = e.clipboardData?.items
      if (!items) return

      for (let i = 0; i < items.length; i++) {
        if (items[i].kind === 'file') {
          const file = items[i].getAsFile()
          if (file && (file.type.startsWith('image/') || file.type.startsWith('video/'))) {
            e.preventDefault()
            processSelectedFile(file)
            break
          }
        }
      }
    }

    window.addEventListener('paste', handlePaste)
    return () => window.removeEventListener('paste', handlePaste)
  }, [])

  // Drag and drop file handling
  function handleDragOver(e) {
    e.preventDefault()
    e.stopPropagation()
    setIsDragOver(true)
  }

  function handleDragLeave(e) {
    e.preventDefault()
    e.stopPropagation()
    setIsDragOver(false)
  }

  function handleDrop(e) {
    e.preventDefault()
    e.stopPropagation()
    setIsDragOver(false)
    const file = e.dataTransfer?.files?.[0]
    if (file && (file.type.startsWith('image/') || file.type.startsWith('video/'))) {
      processSelectedFile(file)
    }
  }

  // Copy text or media link
  async function copyMessageContent(message) {
    const textToCopy = message.text || message.mediaUrl || ''
    if (!textToCopy) return
    try {
      await navigator.clipboard.writeText(textToCopy)
      setCopyFeedbackId(message.id)
      window.setTimeout(() => {
        setCopyFeedbackId((curr) => (curr === message.id ? null : curr))
      }, 1500)
    } catch {
      // fallback
    }
  }

  function triggerReply(message) {
    setReplyToMessage(message)
    setShowAttachmentMenu(false)
    window.setTimeout(() => textInputRef.current?.focus(), 50)
  }

  async function handleFormSubmit(e) {
    e.preventDefault()

    if (sendingRef.current || uploading) return

    const currentReply = replyToMessage

    if (selectedFile) {
      setUploading(true)
      try {
        await sendMedia({ file: selectedFile, caption: text, replyTo: currentReply })
        clearSelectedFile()
        setText('')
        setReplyToMessage(null)
      } catch {
        // notice handled by App.jsx
      } finally {
        setUploading(false)
      }
    } else {
      const trimmed = text.trim()
      if (!trimmed) return

      sendingRef.current = true
      setSending(true)
      try {
        sendMessage(e, currentReply)
        setReplyToMessage(null)
      } finally {
        window.setTimeout(() => {
          sendingRef.current = false
          setSending(false)
        }, 300)
      }
    }
  }

  if (!selectedUser) {
    return (
      <main className="app-screen">
        <header className="chat-header">
          <button className="back-button" onClick={onBack} aria-label="Back to people">
            <Icon name="arrow" size={21} />
          </button>
          <strong>ChatSpace</strong>
        </header>
        <div className="empty-chat">
          <strong>User not found</strong>
          <button className="primary-button small" onClick={onBack}>Back to people</button>
        </div>
      </main>
    )
  }

  return (
    <main
      className={`app-screen chat-screen ${isDragOver ? 'drag-over' : ''}`}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      {/* Drag & drop visual dropzone overlay */}
      {isDragOver && (
        <div className="drag-drop-overlay">
          <div className="drag-drop-card">
            <Icon name="photo" size={44} />
            <strong>Drop photo or video here</strong>
            <span>Add it directly to your conversation</span>
          </div>
        </div>
      )}

      <header className="chat-header">
        <button className="back-button" onClick={onBack} aria-label="Back to people">
          <Icon name="arrow" size={21} />
        </button>
        <span className="chat-avatar-wrap">
          <span
            className="large-avatar"
            style={{ background: getAvatarGradient(selectedUser.id || selectedUser.name) }}
          >
            {selectedUser.name?.charAt(0).toUpperCase()}
          </span>
          <i className={selectedUser.status === 'online' ? 'presence-dot online' : 'presence-dot'} />
        </span>
        <div className="chat-user">
          <strong>{selectedUser.name}</strong>
          <small className={selectedUser.status === 'online' ? 'status-online' : ''}>
            {selectedUser.status === 'online' ? 'Active now' : formatLastSeen(selectedUser.lastSeenAt)}
          </small>
        </div>
        <div className={socketConnected ? 'connection-status online chat-connection' : 'connection-status chat-connection'}>
          <i />{socketConnected ? 'Connected' : 'Connecting'}
        </div>
      </header>

      <section className="chat-body" ref={chatBodyRef} onScroll={handleScroll}>
        {notice && <div className="chat-notice">{notice}</div>}

        {/* Older messages pagination header */}
        {hasMoreOlder && (
          <div className="load-older-bar">
            {loadingOlder ? (
              <span className="loading-older-text">Loading older messages…</span>
            ) : (
              <button
                type="button"
                className="load-older-btn"
                onClick={loadOlderMessages}
              >
                Load older messages
              </button>
            )}
          </div>
        )}

        {chatLoading ? (
          <div className="empty-chat">
            <div className="chat-loading-dot" />
            <span>Loading conversation…</span>
          </div>
        ) : messages.length === 0 ? (
          <div className="empty-chat">
            <span
              className="empty-chat-avatar"
              style={{ background: getAvatarGradient(selectedUser.id || selectedUser.name) }}
            >
              {selectedUser.name?.charAt(0).toUpperCase()}
            </span>
            <strong>Say hello to {selectedUser.name}!</strong>
            <span>Send the first message or photo below.</span>
          </div>
        ) : (
          <div className="messages">
            {messages.map((item, index) => {
              const itemDate = new Date(item.createdAt)
              const previousDate = index > 0 ? new Date(messages[index - 1].createdAt) : null
              const isNewDate = !previousDate || itemDate.toDateString() !== previousDate.toDateString()
              const mediaSrc = getMediaSrc(item.mediaUrl)
              const isMine = item.senderId === user.id
              const isHighlighted = Boolean(
                highlightedMessageId &&
                ((item.id && String(item.id) === highlightedMessageId) ||
                 (item.clientTempId && String(item.clientTempId) === highlightedMessageId))
              )

              return (
                <div
                  key={item.id || item.clientTempId || index}
                  ref={(el) => {
                    if (el) {
                      if (item.id) messageRefs.current[String(item.id)] = el
                      if (item.clientTempId) messageRefs.current[String(item.clientTempId)] = el
                    } else {
                      if (item.id) delete messageRefs.current[String(item.id)]
                      if (item.clientTempId) delete messageRefs.current[String(item.clientTempId)]
                    }
                  }}
                >
                  {isNewDate && (
                    <div className="chat-date-divider">
                      <span>{formatDateBadge(item.createdAt)}</span>
                    </div>
                  )}

                  <div className={`message-line ${isMine ? 'mine' : 'theirs'} ${isHighlighted ? 'highlighted-line' : ''}`}>
                    {/* Hover Message Action Pill */}
                    <div className="message-action-toolbar">
                      <button
                        type="button"
                        className="msg-action-btn"
                        title="Reply to message"
                        aria-label="Reply to message"
                        onClick={() => triggerReply(item)}
                      >
                        <Icon name="reply" size={14} />
                      </button>

                      <button
                        type="button"
                        className="msg-action-btn"
                        title={copyFeedbackId === item.id ? 'Copied!' : 'Copy'}
                        aria-label="Copy message"
                        onClick={() => copyMessageContent(item)}
                      >
                        {copyFeedbackId === item.id ? <Icon name="check" size={14} /> : <Icon name="copy" size={14} />}
                      </button>

                      {isMine && unsendMessage && (
                        <button
                          type="button"
                          className="msg-action-btn unsend"
                          title="Unsend message"
                          aria-label="Unsend message"
                          onClick={() => setUnsendTargetMessage(item)}
                        >
                          <Icon name="trash" size={14} />
                        </button>
                      )}
                    </div>

                    <div className={`message ${animatedMessageIds.has(item.id) ? 'message-new' : ''} ${isHighlighted ? 'message-highlight' : ''}`}>
                      {/* Quoted Reply Section matching mobile */}
                      {item.replyTo && (
                        <div
                          className={`quoted-message-box ${isMine ? 'mine' : 'theirs'}`}
                          onClick={() => handleQuotedMessageClick(item.replyTo.id)}
                          role="button"
                          tabIndex={0}
                          title="Click to view original message"
                        >
                          <div className="quoted-sender">
                            {item.replyTo.senderId === user.id ? 'You' : (item.replyTo.senderName || selectedUser.name)}
                          </div>
                          <div className="quoted-snippet">
                            {item.replyTo.mediaType && (
                              <span className="quoted-media-tag">
                                {item.replyTo.mediaType === 'image' ? '📷 Photo' : item.replyTo.mediaType === 'video' ? '🎥 Video' : '📁 Attachment'}
                              </span>
                            )}
                            {item.replyTo.text && <span>{item.replyTo.text}</span>}
                          </div>
                        </div>
                      )}

                      {/* Attached Media Display */}
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
                                  senderName: isMine ? 'You' : selectedUser.name,
                                  avatar: (isMine ? user.name : selectedUser.name)?.charAt(0)?.toUpperCase() || '?',
                                })
                              }
                            />
                          )}
                        </div>
                      )}

                      {item.text && <span className="message-text">{item.text}</span>}

                      <small className="message-meta">
                        <span>{itemDate.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })}</span>
                        {isMine && (
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

        {/* Floating Quick Scroll to Bottom Button */}
        {showScrollBottom && (
          <button
            type="button"
            className="scroll-to-bottom-btn"
            onClick={() => scrollToBottom(true)}
            aria-label="Scroll to newest messages"
            title="Scroll to bottom"
          >
            {hasNewScrolledMessages && <span className="scroll-bottom-badge" />}
            <Icon name="chevronDown" size={20} />
          </button>
        )}
      </section>

      {/* Replying Banner Dock matching mobile */}
      {replyToMessage && (
        <div className="reply-preview-dock">
          <div className="reply-preview-border" />
          <div className="reply-preview-content">
            <div className="reply-preview-header">
              <Icon name="reply" size={13} />
              <strong>Replying to {replyToMessage.senderId === user.id ? 'You' : (replyToMessage.senderName || selectedUser.name)}</strong>
            </div>
            <div className="reply-preview-snippet">
              {replyToMessage.mediaType && (
                <span className="reply-preview-media">
                  {replyToMessage.mediaType === 'image' ? '📷 Photo' : replyToMessage.mediaType === 'video' ? '🎥 Video' : '📁 Attachment'}
                </span>
              )}
              {replyToMessage.text ? replyToMessage.text : (replyToMessage.mediaName || 'Media')}
            </div>
          </div>
          <button
            type="button"
            className="reply-preview-close"
            onClick={() => setReplyToMessage(null)}
            aria-label="Cancel reply"
            title="Cancel reply (Esc)"
          >
            <Icon name="close" size={16} />
          </button>
        </div>
      )}

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
            <small>{formatBytes(selectedFile.size)}</small>
          </div>
          <button type="button" className="media-preview-clear" onClick={clearSelectedFile} aria-label="Remove attached file">
            <Icon name="close" size={16} />
          </button>
        </div>
      )}

      {/* Message input dock */}
      <form className="message-box" onSubmit={handleFormSubmit}>
        {/* Hidden file inputs */}
        <input
          type="file"
          ref={fileInputRef}
          accept="image/*,video/*"
          style={{ display: 'none' }}
          onChange={handleFileSelect}
        />
        <input
          type="file"
          ref={cameraInputRef}
          accept="image/*"
          capture="environment"
          style={{ display: 'none' }}
          onChange={handleFileSelect}
        />

        {/* Attachment menu trigger */}
        <div className="attachment-menu-wrap">
          <button
            type="button"
            className={`attachment-button ${showAttachmentMenu ? 'active' : ''}`}
            onClick={() => setShowAttachmentMenu(!showAttachmentMenu)}
            disabled={!socketConnected || uploading}
            aria-label="Attach media"
            title="Share photo, video, or camera"
          >
            <Icon name="clip" size={20} />
          </button>

          {/* Attachment Options Popup matching mobile */}
          {showAttachmentMenu && (
            <div className="attachment-dropdown" role="menu">
              <button
                type="button"
                className="attachment-option"
                onClick={() => {
                  setShowAttachmentMenu(false)
                  if (fileInputRef.current) {
                    fileInputRef.current.accept = 'image/*'
                    fileInputRef.current.click()
                  }
                }}
              >
                <div className="option-icon photo"><Icon name="photo" size={18} /></div>
                <span>Photos</span>
              </button>

              <button
                type="button"
                className="attachment-option"
                onClick={() => {
                  setShowAttachmentMenu(false)
                  if (fileInputRef.current) {
                    fileInputRef.current.accept = 'video/*'
                    fileInputRef.current.click()
                  }
                }}
              >
                <div className="option-icon video"><Icon name="video" size={18} /></div>
                <span>Videos</span>
              </button>

              <button
                type="button"
                className="attachment-option"
                onClick={() => {
                  setShowAttachmentMenu(false)
                  cameraInputRef.current?.click()
                }}
              >
                <div className="option-icon camera"><Icon name="camera" size={18} /></div>
                <span>Camera</span>
              </button>
            </div>
          )}
        </div>

        <input
          ref={textInputRef}
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault()
              handleFormSubmit(e)
            }
          }}
          placeholder={selectedFile ? 'Add a caption…' : replyToMessage ? 'Write a reply…' : 'Write a message…'}
          disabled={!socketConnected || uploading || sending}
          autoComplete="off"
        />

        <button
          type="submit"
          aria-label="Send message"
          disabled={!socketConnected || (!text.trim() && !selectedFile) || uploading || sending}
        >
          {uploading ? (
            <span>Uploading…</span>
          ) : sending ? (
            <span>Sending…</span>
          ) : (
            <>
              <Icon name="send" size={19} />
              <span>Send</span>
            </>
          )}
        </button>
      </form>

      {/* Styled Unsend Confirmation Dialog matching mobile */}
      {unsendTargetMessage && (
        <div
          className="dialog-backdrop"
          role="presentation"
          onMouseDown={(e) => {
            if (e.target === e.currentTarget) setUnsendTargetMessage(null)
          }}
        >
          <section
            className="logout-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="unsend-dialog-title"
          >
            <div className="logout-dialog-icon unsend-icon">
              <Icon name="trash" size={22} />
            </div>
            <h2 id="unsend-dialog-title">Unsend this message?</h2>
            <p>
              This will remove the message for everyone in the chat.
            </p>
            <div className="logout-dialog-actions">
              <button
                type="button"
                className="dialog-cancel"
                onClick={() => setUnsendTargetMessage(null)}
              >
                Cancel
              </button>
              <button
                type="button"
                className="dialog-confirm unsend-confirm"
                onClick={() => {
                  const targetId = unsendTargetMessage.id
                  setUnsendTargetMessage(null)
                  unsendMessage(targetId)
                }}
              >
                Unsend
              </button>
            </div>
          </section>
        </div>
      )}

      {/* Full-Screen Instagram-Style In-App Photo & Video Preview */}
      {activeMediaModal && (
        <div
          className="insta-preview-overlay"
          onClick={() => setActiveMediaModal(null)}
          role="dialog"
          aria-modal="true"
        >
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
