import { useState } from 'react'

export default function RegisterPage({ loading, notice, onSubmit, onLogin }) {
  const [form, setForm] = useState({ name: '', username: '', password: '', phone: '' })
  function update(e) { setForm((current) => ({ ...current, [e.target.name]: e.target.value })) }
  function submit(e) { e.preventDefault(); onSubmit(form) }

  return (
    <main className="auth-screen">
      <section className="auth-panel">
        <div className="auth-brand"><div className="brand-mark">◌</div><strong>ChatSpace</strong></div>
        <div className="auth-copy"><span className="eyebrow">CREATE ACCOUNT</span><h1>Start your private<br />conversation space.</h1><p>Create an account and connect with people in real time.</p></div>
        <form className="auth-form" onSubmit={submit}>
          <label>Full name<input name="name" value={form.name} onChange={update} placeholder="Your name" required /></label>
          <label>Email address<input name="username" type="email" value={form.username} onChange={update} placeholder="you@example.com" required /></label>
          <label>Password<input name="password" type="password" value={form.password} onChange={update} placeholder="Create a password" required /></label>
          <label>Phone <span className="optional">Optional</span><input name="phone" value={form.phone} onChange={update} placeholder="+91 98765 43210" /></label>
          {notice && <div className="auth-error">{notice}</div>}
          <button className="primary-button" disabled={loading}>{loading ? 'Creating account…' : 'Create account'}</button>
        </form>
        <p className="auth-switch">Already have an account? <button onClick={onLogin}>Sign in</button></p>
      </section>
    </main>
  )
}
