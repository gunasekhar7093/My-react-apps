export default function LoginPage({ form, updateField, submit, loading, notice, goRegister }) {
  return (
    <main className="auth-page">
      <section className="auth-card">
        <div className="auth-brand"><div className="brand-mark">💬</div><strong>ChatSpace</strong></div>
        <div className="auth-heading">
          <span className="eyebrow">WELCOME BACK</span>
          <h1>Sign in</h1>
          <p>Continue to your private conversations.</p>
        </div>
        <form className="auth-form" onSubmit={submit}>
          <label>Email address
            <input name="username" type="email" value={form.username} onChange={updateField} placeholder="you@example.com" autoComplete="email" required />
          </label>
          <label>Password
            <input name="password" type="password" value={form.password} onChange={updateField} placeholder="Your password" autoComplete="current-password" required />
          </label>
          <button className="auth-submit" disabled={loading}>{loading ? 'Signing in…' : 'Sign in'}</button>
        </form>
        {notice && <div className="auth-notice">{notice}</div>}
        <p className="auth-switch">Don't have an account? <button type="button" onClick={goRegister}>Create account</button></p>
      </section>
    </main>
  )
}
