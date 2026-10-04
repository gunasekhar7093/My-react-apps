export default function RegisterPage({ form, updateField, submit, loading, notice, goLogin }) {
  return (
    <main className="auth-page">
      <section className="auth-card">
        <div className="auth-brand"><div className="brand-mark">💬</div><strong>ChatSpace</strong></div>
        <div className="auth-heading">
          <span className="eyebrow">GET STARTED</span>
          <h1>Create account</h1>
          <p>Join ChatSpace and start private conversations.</p>
        </div>
        <form className="auth-form" onSubmit={submit}>
          <label>Full name
            <input name="name" value={form.name} onChange={updateField} placeholder="Your name" autoComplete="name" required />
          </label>
          <label>Phone <span>Optional</span>
            <input name="phone" value={form.phone} onChange={updateField} placeholder="+91 98765 43210" autoComplete="tel" />
          </label>
          <label>Email address
            <input name="username" type="email" value={form.username} onChange={updateField} placeholder="you@example.com" autoComplete="email" required />
          </label>
          <label>Password
            <input name="password" type="password" value={form.password} onChange={updateField} placeholder="At least 6 characters" autoComplete="new-password" required />
          </label>
          <button className="auth-submit" disabled={loading}>{loading ? 'Creating account…' : 'Create account'}</button>
        </form>
        {notice && <div className="auth-notice">{notice}</div>}
        <p className="auth-switch">Already have an account? <button type="button" onClick={goLogin}>Sign in</button></p>
      </section>
    </main>
  )
}
