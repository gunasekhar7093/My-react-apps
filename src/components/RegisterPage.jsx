import { useState } from 'react'

export default function RegisterPage({ loading, notice, onSubmit, onLogin }) {
  const [form, setForm] = useState({ name: '', username: '', password: '', phone: '' })
  const [localError, setLocalError] = useState('')

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
            <label>Password<input name="password" type="password" value={form.password} onChange={update} placeholder="Create a password" autoComplete="new-password" required /></label>
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
