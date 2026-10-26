export const avatarGradients = [
  ['#6366F1', '#8B5CF6'],
  ['#3B82F6', '#06B6D4'],
  ['#EC4899', '#F43F5E'],
  ['#F59E0B', '#D97706'],
  ['#10B981', '#059669'],
  ['#8B5CF6', '#D946EF'],
  ['#0EA5E9', '#2563EB'],
  ['#14B8A6', '#0D9488'],
]

export function getAvatarGradient(key = '') {
  if (!key) return `linear-gradient(135deg, ${avatarGradients[0][0]}, ${avatarGradients[0][1]})`
  let hash = 0
  for (let i = 0; i < key.length; i++) {
    hash += key.charCodeAt(i)
  }
  const pair = avatarGradients[Math.abs(hash) % avatarGradients.length]
  return `linear-gradient(135deg, ${pair[0]}, ${pair[1]})`
}

export function formatDateBadge(dateStr) {
  if (!dateStr) return ''
  const date = new Date(dateStr)
  if (Number.isNaN(date.getTime())) return ''
  const now = new Date()
  const isToday = date.toDateString() === now.toDateString()
  const yesterday = new Date(now)
  yesterday.setDate(now.getDate() - 1)
  const isYesterday = date.toDateString() === yesterday.toDateString()

  if (isToday) return 'Today'
  if (isYesterday) return 'Yesterday'
  return date.toLocaleDateString('en-GB', { day: '2-digit', month: '2-digit', year: 'numeric' })
}

export function formatBytes(bytes) {
  if (!bytes || bytes <= 0) return '0 B'
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB'
}
