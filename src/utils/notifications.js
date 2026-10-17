/**
 * Request notification permissions from the user.
 */
export async function requestNotificationPermission() {
  if (!('Notification' in window)) return 'unsupported'
  if (Notification.permission === 'default') {
    try {
      return await Notification.requestPermission()
    } catch {
      return 'denied'
    }
  }
  return Notification.permission
}

/**
 * Display a desktop notification for an incoming message with WhatsApp style.
 */
export function showWebNotification({ title, body, icon, onClick }) {
  if (!('Notification' in window)) return null
  if (Notification.permission !== 'granted') return null

  try {
    const notification = new Notification(title, {
      body,
      icon: icon || '/vite.svg',
      tag: 'chatspace-msg-' + Date.now(),
      renotify: true,
      silent: true, // Audio chime is played via Web Audio API
    })

    notification.onclick = () => {
      window.focus()
      onClick?.()
      notification.close()
    }

    return notification
  } catch (e) {
    console.warn('Failed to show desktop notification:', e)
    return null
  }
}
