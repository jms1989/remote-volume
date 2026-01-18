const { app, Tray, Menu, nativeImage } = require('electron');
const path = require('path');
const WebSocket = require('ws');
const Store = require('electron-store');
const volumeController = require('./volumeController');

// Initialize store for persistent settings
const store = new Store();

// Set default values if not present
if (!store.has('port')) {
  store.set('port', 8080);
}
if (!store.has('pollingEnabled')) {
  store.set('pollingEnabled', true);
}
if (!store.has('pollingInterval')) {
  store.set('pollingInterval', 500);
}
if (!store.has('autostart')) {
  store.set('autostart', false);
}

let tray = null;
let wss = null;
let pollingTimer = null;
let lastVolume = null;
let lastMute = null;

// Start WebSocket server
function startWebSocketServer() {
  const port = store.get('port');
  
  wss = new WebSocket.Server({ port });
  
  console.log(`WebSocket server started on port ${port}`);
  
  wss.on('connection', (ws) => {
    console.log('Client connected');
    
    // Send current state on connection
    sendState(ws);
    
    ws.on('message', async (message) => {
      try {
        const data = JSON.parse(message);
        await handleMessage(data, ws);
      } catch (error) {
        console.error('Error handling message:', error);
        ws.send(JSON.stringify({ error: error.message }));
      }
    });
    
    ws.on('close', () => {
      console.log('Client disconnected');
    });
  });
}

// Handle incoming WebSocket messages
async function handleMessage(data, ws) {
  const { action, value } = data;
  
  switch (action) {
    case 'setVolume':
      await volumeController.setVolume(value);
      broadcastState();
      break;
      
    case 'getState':
      sendState(ws);
      break;
      
    case 'increaseVolume':
      const currentVol = await volumeController.getVolume();
      await volumeController.setVolume(Math.min(100, currentVol + value));
      broadcastState();
      break;
      
    case 'decreaseVolume':
      const vol = await volumeController.getVolume();
      await volumeController.setVolume(Math.max(0, vol - value));
      broadcastState();
      break;
      
    case 'mute':
      await volumeController.setMuted(true);
      broadcastState();
      break;
      
    case 'unmute':
      await volumeController.setMuted(false);
      broadcastState();
      break;
      
    case 'toggleMute':
      const isMuted = await volumeController.getMuted();
      await volumeController.setMuted(!isMuted);
      broadcastState();
      break;
      
    case 'isMuted':
      sendState(ws);
      break;
      
    default:
      ws.send(JSON.stringify({ error: 'Unknown action' }));
  }
}

// Send current state to a specific client
async function sendState(ws) {
  try {
    const volume = await volumeController.getVolume();
    const muted = await volumeController.getMuted();
    const device = await volumeController.getOutputDevice();
    
    ws.send(JSON.stringify({
      volume,
      muted,
      device
    }));
  } catch (error) {
    console.error('Error getting state:', error);
  }
}

// Broadcast state to all connected clients
async function broadcastState() {
  if (!wss) return;
  
  try {
    const volume = await volumeController.getVolume();
    const muted = await volumeController.getMuted();
    const device = await volumeController.getOutputDevice();
    
    const state = JSON.stringify({ volume, muted, device });
    
    wss.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(state);
      }
    });
  } catch (error) {
    console.error('Error broadcasting state:', error);
  }
}

// Start polling if enabled
function startPolling() {
  const enabled = store.get('pollingEnabled');
  const interval = store.get('pollingInterval');
  
  if (enabled) {
    pollingTimer = setInterval(async () => {
      try {
        const volume = await volumeController.getVolume();
        const muted = await volumeController.getMuted();
        
        // Only broadcast if something changed
        if (volume !== lastVolume || muted !== lastMute) {
          lastVolume = volume;
          lastMute = muted;
          broadcastState();
        }
      } catch (error) {
        console.error('Error polling:', error);
      }
    }, interval);
  }
}

function stopPolling() {
  if (pollingTimer) {
    clearInterval(pollingTimer);
    pollingTimer = null;
  }
}

// Create system tray
function createTray() {
  // Create tray icon
  const iconPath = path.join(__dirname, 'menuicon.png');
  const icon = nativeImage.createFromPath(iconPath);
  tray = new Tray(icon.resize({ width: 16, height: 16 }));
  
  const contextMenu = Menu.buildFromTemplate([
    {
      label: 'Remote Volume',
      enabled: false
    },
    {
      type: 'separator'
    },
    {
      label: `Port: ${store.get('port')}`,
      enabled: false
    },
    {
      label: `Polling: ${store.get('pollingEnabled') ? 'ON' : 'OFF'}`,
      enabled: false
    },
    {
      type: 'separator'
    },
    {
      label: 'Quit',
      click: () => {
        app.quit();
      }
    }
  ]);
  
  tray.setToolTip('Remote Volume - Running in background');
  tray.setContextMenu(contextMenu);
}

// App ready
app.whenReady().then(() => {
  console.log('Remote Volume starting in headless mode...');
  console.log('Settings:');
  console.log(`  Port: ${store.get('port')}`);
  console.log(`  Polling: ${store.get('pollingEnabled')}`);
  console.log(`  Polling Interval: ${store.get('pollingInterval')}ms`);
  
  createTray();
  startWebSocketServer();
  startPolling();
});

// Cleanup on quit
app.on('before-quit', () => {
  stopPolling();
  if (wss) {
    wss.close();
  }
});

// Prevent app from quitting when all windows are closed (headless mode)
app.on('window-all-closed', (e) => {
  e.preventDefault();
});
