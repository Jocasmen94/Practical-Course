const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 8080;

app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/api/hello', (req, res) => {
  res.json({
    message: 'Hola desde el Backend! Deploy automatico via OIDC + GitHub Actions',
    hostname: require('os').hostname(),
    version: process.env.APP_VERSION || 'v2.0.0',
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString()
  });
});

app.get('/api/users', (req, res) => {
  res.json({
    users: [
      { id: 1, name: 'Javier', role: 'DevOps' },
      { id: 2, name: 'Maria', role: 'Developer' },
      { id: 3, name: 'Carlos', role: 'SRE' }
    ]
  });
});

app.listen(PORT, () => {
  console.log(`Backend running on port ${PORT}`);
});
