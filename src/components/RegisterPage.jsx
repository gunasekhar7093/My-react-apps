import { useState } from 'react'

const EyeIcon = ({ show }) => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    {show ? (
      <>
        <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z" />
        <circle cx="12" cy="12" r="3" />
      </>
    ) : (
      <>
        <path d="M9.88 9.88a3 3 0 1 0 4.24 4.24" />
        <path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68" />
        <path d="M6.61 6.61A13.526 13.526 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61" />
        <line x1="2" x2="22" y1="2" y2="22" />
      </>
    )}
  </svg>
)

export default function RegisterPage({ loading, notice, onSubmit, onLogin }) {
  const [form, setForm] = useState({ name: '', username: '', password: '', phone: '' })
  const [localError, setLocalError] = useState('')
  const [showPassword, setShowPassword] = useState(false)

  function update(e) {
    setLocalError('')
    setForm((current) => ({ ...current, [e.target.name]: e.target.value }))
  }

  function submit(e) {
    e.preventDefault()
    setLocalError('')
    if (form.name.trim().length < 2) {
      setLocalError('Name must be at least 2 characters')
      return
    }
    const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/
    if (!emailRegex.test(form.username.trim())) {
      setLocalError('Please enter a valid email address (e.g. name@example.com)')
      return
    }
    if (form.password.length < 6) {
      setLocalError('Password must be at least 6 characters')
      return
    }
    onSubmit(form)
  }

  return (
    <main className="auth-screen">
      <section className="auth-shell">
        <div className="auth-showcase">
          <div className="showcase-brand"><span className="brand-mark">C</span><strong>ChatSpace</strong></div>
          <div className="showcase-content"><span className="eyebrow">YOUR PRIVATE SPACE</span><h1>Bring your people<br /><em>closer together.</em></h1><p>Create your account and start messaging in real time.</p></div>
          <div className="showcase-footer"><span className="showcase-dot" /> Secure session · Real-time presence</div>
        </div>
        <div className="auth-panel">
          <div className="auth-mobile-brand"><span className="brand-mark">C</span><strong>ChatSpace</strong></div>
          <div className="auth-copy"><span className="eyebrow">GET STARTED</span><h2>Create your account</h2><p>It only takes a moment to join.</p></div>
          <form className="auth-form" onSubmit={submit}>
            <label>Full name<input name="name" value={form.name} onChange={update} placeholder="Your name" autoComplete="name" required /></label>
            <label>Email address<input name="username" type="email" value={form.username} onChange={update} placeholder="you@example.com" autoComplete="email" required /></label>
            <label>
              Password
              <div className="password-input-wrap">
                <input
                  name="password"
                  type={showPassword ? 'text' : 'password'}
                  value={form.password}
                  onChange={update}
                  placeholder="Create a password"
                  autoComplete="new-password"
                  required
                />
                <button
                  type="button"
                  className="password-toggle-btn"
                  onClick={() => setShowPassword(!showPassword)}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  <EyeIcon show={showPassword} />
                </button>
              </div>
            </label>
            <label>Phone <span className="optional">Optional</span><input name="phone" value={form.phone} onChange={update} placeholder="+91 98765 43210" autoComplete="tel" /></label>
            {(localError || notice) && <div className="auth-error">{localError || notice}</div>}
            <button className="primary-button" disabled={loading}>{loading ? 'Creating account…' : 'Create account'}</button>
          </form>
          <p className="auth-switch">Already have an account? <button onClick={onLogin}>Sign in</button></p>
        </div>
      </section>
    </main>
  )
}
