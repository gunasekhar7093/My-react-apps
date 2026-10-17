let audioCtx = null

/**
 * Play a WhatsApp-like melodic message arrival chime using the Web Audio API.
 * Requires no external audio assets and works in all modern browsers.
 */
export function playMessageChime() {
  try {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    if (!AudioContextClass) return

    if (!audioCtx) {
      audioCtx = new AudioContextClass()
    }

    if (audioCtx.state === 'suspended') {
      audioCtx.resume()
    }

    const now = audioCtx.currentTime

    // Tone 1: 587.33 Hz (D5) - gentle start note
    const osc1 = audioCtx.createOscillator()
    const gain1 = audioCtx.createGain()
    osc1.type = 'sine'
    osc1.frequency.setValueAtTime(587.33, now)
    gain1.gain.setValueAtTime(0.0001, now)
    gain1.gain.exponentialRampToValueAtTime(0.24, now + 0.02)
    gain1.gain.exponentialRampToValueAtTime(0.0001, now + 0.15)
    osc1.connect(gain1)
    gain1.connect(audioCtx.destination)
    osc1.start(now)
    osc1.stop(now + 0.15)

    // Tone 2: 880 Hz (A5) - bright bell-like finish
    const osc2 = audioCtx.createOscillator()
    const gain2 = audioCtx.createGain()
    osc2.type = 'sine'
    osc2.frequency.setValueAtTime(880, now + 0.09)
    gain2.gain.setValueAtTime(0.0001, now + 0.09)
    gain2.gain.exponentialRampToValueAtTime(0.28, now + 0.11)
    gain2.gain.exponentialRampToValueAtTime(0.0001, now + 0.45)
    osc2.connect(gain2)
    gain2.connect(audioCtx.destination)
    osc2.start(now + 0.09)
    osc2.stop(now + 0.45)
  } catch (err) {
    console.warn('Audio chime error:', err)
  }
}
