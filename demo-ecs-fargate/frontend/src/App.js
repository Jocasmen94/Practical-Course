import React, { useState, useEffect } from 'react';

function App() {
  const [message, setMessage] = useState(null);
  const [users, setUsers] = useState([]);
  const [error, setError] = useState(null);

  const API_URL = process.env.REACT_APP_API_URL || '/api';

  useEffect(() => {
    fetch(`${API_URL}/hello`)
      .then(res => res.json())
      .then(data => setMessage(data))
      .catch(err => setError(err.message));

    fetch(`${API_URL}/users`)
      .then(res => res.json())
      .then(data => setUsers(data.users))
      .catch(err => setError(err.message));
  }, [API_URL]);

  return (
    <div style={{
      fontFamily: 'Arial',
      maxWidth: 800,
      margin: '50px auto',
      padding: 20,
      background: 'linear-gradient(135deg, #667eea, #764ba2)',
      minHeight: '100vh',
      color: 'white'
    }}>
      <h1>Demo ECS Fargate</h1>
      <p>Frontend React + Backend Node.js en AWS ECS Fargate</p>

      {error && (
        <div style={{ background: '#ff4444', padding: 15, borderRadius: 8 }}>
          Error: {error}
        </div>
      )}

      {message && (
        <div style={{ background: 'rgba(255,255,255,0.1)', padding: 20, borderRadius: 8, marginTop: 20 }}>
          <h2>Respuesta del Backend</h2>
          <p><strong>Mensaje:</strong> {message.message}</p>
          <p><strong>Hostname:</strong> {message.hostname}</p>
          <p><strong>Versión:</strong> {message.version}</p>
          <p><strong>Ambiente:</strong> {message.environment}</p>
          <p><strong>Timestamp:</strong> {message.timestamp}</p>
        </div>
      )}

      <div style={{ background: 'rgba(255,255,255,0.1)', padding: 20, borderRadius: 8, marginTop: 20 }}>
        <h2>Usuarios</h2>
        <ul>
          {users.map(user => (
            <li key={user.id}>
              <strong>{user.name}</strong> - {user.role}
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

export default App;
