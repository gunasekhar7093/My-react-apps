import { useState } from 'react'

export default function LoginPage({ loading, notice, onSubmit, onRegister }) {
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')

  function submit(e) {
    e.preventDefault()
    onSubmit({ username, password })
  }

  return (
    <main className="auth-screen">
      <section className="auth-panel">
        <div className="auth-brand"><div className="brand-mark">◌</div><strong>ChatSpace</strong></div>
        <div className="auth-copy"><span className="eyebrow">WELCOME BACK</span><h1>Private conversations,<br />beautifully simple.</h1><p>Sign in to continue to your conversations.</p></div>
        <form className="auth-form" onSubmit={submit}>
          <label>Email address<input type="email" value={username} onChange={(e) => setUsername(e.target.value)} placeholder="you@example.com" autoComplete="email" required /></label>
          <label>Password<input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Your password" autoComplete="current-password" required /></label>
          {notice && <div className="auth-error">{notice}</div>}
          <button className="primary-button" disabled={loading}>{loading ? 'Signing in…' : 'Sign in'}</button>
        </form>
        <p className="auth-switch">Don't have an account? <button onClick={onRegister}>Create account</button></p>
      </section>
    </main>
  )
}
