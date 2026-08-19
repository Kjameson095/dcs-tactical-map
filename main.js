const { app, BrowserWindow, dialog } = require('electron');
const path = require('path');
const dgram = require('dgram');
const WebSocket = require('ws');
const fs = require('fs');
const os = require('os');
const { autoUpdater } = require('electron-updater');

// --- 1. DCS LUA AUTO-INSTALLER ---
function installDcsExport() {
    const requireLine = `\n-- DCS Tactical Map Hook\npcall(function() dofile(lfs.writedir()..[[Scripts\\TacticalMapExport.lua]]) end, log.info("Tactical Map loaded"))\n`;
    const savedGamesPath = path.join(os.homedir(), 'Saved Games');
    const dcsFolders = ['DCS', 'DCS.openbeta'];

    dcsFolders.forEach(folder => {
        const dcsPath = path.join(savedGamesPath, folder);
        const scriptsDir = path.join(dcsPath, 'Scripts');
        
        if (fs.existsSync(dcsPath)) {
            if (!fs.existsSync(scriptsDir)) {
                fs.mkdirSync(scriptsDir, { recursive: true });
            }

            const sourceLua = path.join(__dirname, 'TacticalMapExport.lua');
            const destLua = path.join(scriptsDir, 'TacticalMapExport.lua');
            
            if (fs.existsSync(sourceLua)) {
                fs.copyFileSync(sourceLua, destLua);
            }

            const exportFilePath = path.join(scriptsDir, 'Export.lua');
            
            if (fs.existsSync(exportFilePath)) {
                const currentExport = fs.readFileSync(exportFilePath, 'utf8');
                if (!currentExport.includes('TacticalMapExport.lua')) {
                    fs.appendFileSync(exportFilePath, requireLine);
                }
            } else {
                fs.writeFileSync(exportFilePath, requireLine);
            }
        }
    });
}

// --- 2. START INTERNAL BACKEND SERVER ---
const udpPort = 50000;
const wsPort = 8080;
const wss = new WebSocket.Server({ port: wsPort });

const server = dgram.createSocket('udp4');

server.on('message', (msg, rinfo) => {
    wss.clients.forEach(function each(client) {
        if (client.readyState === WebSocket.OPEN) {
            client.send(msg.toString());
        }
    });
});

server.bind(udpPort);

// --- 3. START ELECTRON DESKTOP APP ---
function createWindow () {
    const win = new BrowserWindow({
        width: 1280,
        height: 720,
        title: "DCS Tactical Map",
        autoHideMenuBar: true, 
        backgroundColor: '#111111',
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false
        }
    });

    win.loadFile('index.html');
}

app.whenReady().then(() => {
    installDcsExport();
    createWindow();

    // Silently check GitHub for updates when the app launches
    autoUpdater.checkForUpdatesAndNotify();

    app.on('activate', () => {
        if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
});

// --- 4. AUTO-UPDATER EVENTS ---
// When the background download is fully complete, prompt the user
autoUpdater.on('update-downloaded', (info) => {
    dialog.showMessageBox({
        type: 'info',
        title: 'Update Available',
        message: `A new version of DCS Tactical Map (${info.version}) has been downloaded.\n\nWould you like to install it and restart now?`,
        buttons: ['Restart and Install', 'Later']
    }).then((result) => {
        if (result.response === 0) {
            autoUpdater.quitAndInstall(false, true); // Quits the app and runs the installer silently
        }
    });
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
});