const { app, BrowserWindow } = require('electron');
const path = require('path');
const dgram = require('dgram');
const WebSocket = require('ws');

// --- 1. START INTERNAL BACKEND SERVER ---
const udpPort = 50000;
const wsPort = 8080;

// Start WebSocket Server (Communicates with your index.html)
const wss = new WebSocket.Server({ port: wsPort });

wss.on('connection', function connection(ws) {
    console.log('Map frontend connected to internal WebSocket server.');
});

// Start UDP Server (Listens to DCS Export.lua)
const server = dgram.createSocket('udp4');

server.on('error', (err) => {
    console.log(`UDP server error:\n${err.stack}`);
    server.close();
});

server.on('message', (msg, rinfo) => {
    // Instantly rebroadcast the DCS telemetry to the map interface
    wss.clients.forEach(function each(client) {
        if (client.readyState === WebSocket.OPEN) {
            client.send(msg.toString());
        }
    });
});

server.bind(udpPort, () => {
    console.log(`Internal UDP server listening for DCS telemetry on port ${udpPort}`);
});


// --- 2. START ELECTRON DESKTOP APP ---
function createWindow () {
    const win = new BrowserWindow({
        width: 1280,
        height: 720,
        title: "DCS Tactical Map",
        autoHideMenuBar: true, // Hides the standard File/Edit menu
        backgroundColor: '#111111',
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false
        }
    });

    win.loadFile('index.html');
}

app.whenReady().then(() => {
    createWindow();

    app.on('activate', () => {
        if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
});