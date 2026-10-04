import React from 'react'
import { createRoot } from 'react-dom/client'
import './style.css'

function App() {
  return (
    <main className="app">
      <div className="card">
        <h1>My React Apps</h1>
        <p>Your React + Vite app is successfully deployed.</p>
        <span>Vite • React • Vercel</span>
      </div>
    </main>
  )
}

createRoot(document.getElementById('root')).render(
  <React.StrictMode><App /></React.StrictMode>
)