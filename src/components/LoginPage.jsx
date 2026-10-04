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
      <section className="auth-shell">
        <div className="auth-showcase">
          <div className="showcase-brand"><span className="brand-mark">C</span><strong>ChatSpace</strong></div>
          <div className="showcase-content">
            <span className="eyebrow">PRIVATE. SIMPLE. REAL-TIME.</span>
            <h1>Conversations that<br /><em>feel effortless.</em></h1>
            <p>Connect with your people through a focused, private messaging experience.</p>
          </div>
          <div className="showcase-footer"><span className="showcase-dot" /> Real-time messaging · Always connected</div>
        </div>
        <div className="auth-panel">
          <div className="auth-mobile-brand"><span className="brand-mark">C</span><strong>ChatSpace</strong></div>
          <div className="auth-copy"><span className="eyebrow">WELCOME BACK</span><h2>Sign in to your space</h2><p>Enter your details to continue.</p></div>
          <form className="auth-form" onSubmit={submit}>
            <label>Email address<input type="email" value={username} onChange={(e) => setUsername(e.target.value)} placeholder="you@example.com" autoComplete="email" required /></label>
            <label>Password<input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Your password" autoComplete="current-password" required /></label>
            {notice && <div className="auth-error">{notice}</div>}
            <button className="primary-button" disabled={loading}>{loading ? 'Signing in…' : 'Sign in'}</button>
          </form>
          <p className="auth-switch">Don't have an account? <button onClick={onRegister}>Create account</button></p>
        </div>
      </section>
    </main>
  )
}
