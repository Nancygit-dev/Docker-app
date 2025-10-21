const express = require('express');
const path = require('path');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Routes
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/health', (req, res) => {
    res.json({
        status: 'OK',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        memory: process.memoryUsage(),
        environment: process.env.NODE_ENV || 'development'
    });
});

app.get('/api/info', (req, res) => {
    res.json({
        name: 'Docker Web App',
        version: '1.0.0',
        description: 'A simple Dockerized application for DevOps testing',
        server: {
            host: req.hostname,
            ip: req.ip,
            protocol: req.protocol
        },
        system: {
            nodeVersion: process.version,
            platform: process.platform,
            architecture: process.arch
        }
    });
});

app.get('/api/greet/:name?', (req, res) => {
    const name = req.params.name || 'World';
    res.json({
        message: `Hello, ${name}!`,
        timestamp: new Date().toISOString()
    });
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).json({ 
        error: 'Something went wrong!',
        message: err.message 
    });
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({ 
        error: 'Endpoint not found',
        path: req.path 
    });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
    console.log(`
    🚀 Server is running!
    📍 Port: ${PORT}
    🌐 Environment: ${process.env.NODE_ENV || 'development'}
    🐳 Containerized: ${process.env.DOCKER_ENV ? 'Yes' : 'No'}
    📅 Started: ${new Date().toISOString()}
    `);
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\n🛑 Received SIGINT. Shutting down gracefully...');
    process.exit(0);
});

process.on('SIGTERM', () => {
    console.log('\n🛑 Received SIGTERM. Shutting down gracefully...');
    process.exit(0);
});

