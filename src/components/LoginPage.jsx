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

export default function LoginPage({ loading, notice, onSubmit, onRegister }) {
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)

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
            <label>
              Email address
              <input
                type="email"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="you@example.com"
                autoComplete="email"
                required
              />
            </label>
            <label>
              Password
              <div className="password-input-wrap">
                <input
                  type={showPassword ? 'text' : 'password'}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Your password"
                  autoComplete="current-password"
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
            {notice && <div className="auth-error">{notice}</div>}
            <button className="primary-button" disabled={loading}>{loading ? 'Signing in…' : 'Sign in'}</button>
          </form>
          <p className="auth-switch">Don't have an account? <button onClick={onRegister}>Create account</button></p>
        </div>
      </section>
    </main>
  )
}
