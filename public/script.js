// API endpoints
const API_BASE = '/api';
const HEALTH_ENDPOINT = '/health';
const INFO_ENDPOINT = '/api/info';

// Check application health
async function checkHealth() {
    try {
        const response = await fetch(HEALTH_ENDPOINT);
        const data = await response.json();
        
        const statusElement = document.getElementById('status');
        statusElement.className = 'status-healthy';
        statusElement.innerHTML = `
            <strong>Status:</strong> ${data.status}<br>
            <strong>Uptime:</strong> ${Math.round(data.uptime)} seconds<br>
            <strong>Environment:</strong> ${data.environment}<br>
            <strong>Last Check:</strong> ${new Date().toLocaleTimeString()}
        `;
    } catch (error) {
        const statusElement = document.getElementById('status');
        statusElement.className = 'status-error';
        statusElement.textContent = 'Unable to connect to application';
        console.error('Health check failed:', error);
    }
}

// Load system information
async function loadSystemInfo() {
    try {
        const response = await fetch(INFO_ENDPOINT);
        const data = await response.json();
        
        const systemInfoElement = document.getElementById('system-info');
        systemInfoElement.innerHTML = `
            <strong>App Version:</strong> ${data.version}<br>
            <strong>Node.js:</strong> ${data.system.nodeVersion}<br>
            <strong>Platform:</strong> ${data.system.platform}<br>
            <strong>Architecture:</strong> ${data.system.architecture}<br>
            <strong>Server Host:</strong> ${data.server.host}
        `;
    } catch (error) {
        document.getElementById('system-info').textContent = 'Failed to load system info';
        console.error('System info load failed:', error);
    }
}

// Greet function
async function greet() {
    const nameInput = document.getElementById('nameInput');
    const name = nameInput.value.trim();
    const resultElement = document.getElementById('greet-result');
    
    try {
        const endpoint = name ? `/api/greet/${encodeURIComponent(name)}` : '/api/greet';
        const response = await fetch(endpoint);
        const data = await response.json();
        
        resultElement.innerHTML = `
            <strong>Response:</strong> ${data.message}<br>
            <strong>Time:</strong> ${new Date(data.timestamp).toLocaleTimeString()}
        `;
    } catch (error) {
        resultElement.innerHTML = '<strong>Error:</strong> Unable to reach greet API';
        console.error('Greet API call failed:', error);
    }
}

// Initialize application
document.addEventListener('DOMContentLoaded', function() {
    checkHealth();
    loadSystemInfo();
    
    // Refresh health status every 30 seconds
    setInterval(checkHealth, 30000);
    
    // Add enter key support for greet input
    document.getElementById('nameInput').addEventListener('keypress', function(e) {
        if (e.key === 'Enter') {
            greet();
        }
    });
});
