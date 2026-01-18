#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Remote Volume Headless Builder${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    echo -e "${RED}Error: package.json not found.${NC}"
    echo "Please run this script from the remote-volume directory"
    exit 1
fi

echo -e "${YELLOW}Step 1: Backing up original files${NC}"
cp main.js main.js.backup 2>/dev/null || echo "main.js.backup already exists"
cp volumeController.js volumeController.js.backup 2>/dev/null || echo "volumeController.js.backup already exists"
cp package.json package.json.backup 2>/dev/null || echo "package.json.backup already exists"

echo -e "${YELLOW}Step 2: Creating headless main.js${NC}"
cat > main.js << 'MAINJS_EOF'
const { app, Tray, Menu, nativeImage } = require('electron');
const path = require('path');
const WebSocket = require('ws');
const Store = require('electron-store');
const volumeController = require('./volumeController');

// Initialize store for persistent settings
const store = new Store();

// Set default values if not present
if (!store.has('port')) {
  store.set('port', 2501);
}
if (!store.has('pollingEnabled')) {
  store.set('pollingEnabled', true);
}
if (!store.has('pollingInterval')) {
  store.set('pollingInterval', 100);
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
MAINJS_EOF

echo -e "${GREEN}✓ Created headless main.js${NC}"

echo -e "${YELLOW}Step 3: Creating CommonJS volumeController.js${NC}"
cat > volumeController.js << 'VOLUMECTRL_EOF'
const os = require('os');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

const platform = os.platform();

// Linux volume control using amixer
async function getVolumeLinux() {
  try {
    const { stdout } = await execAsync('amixer get Master');
    const match = stdout.match(/\[(\d+)%\]/);
    return match ? parseInt(match[1]) : 0;
  } catch (error) {
    console.error('Error getting volume:', error);
    return 0;
  }
}

async function setVolumeLinux(volume) {
  try {
    await execAsync(`amixer set Master ${volume}%`);
  } catch (error) {
    console.error('Error setting volume:', error);
  }
}

async function getMutedLinux() {
  try {
    const { stdout } = await execAsync('amixer get Master');
    return stdout.includes('[off]');
  } catch (error) {
    console.error('Error getting mute state:', error);
    return false;
  }
}

async function setMutedLinux(muted) {
  try {
    await execAsync(`amixer set Master ${muted ? 'mute' : 'unmute'}`);
  } catch (error) {
    console.error('Error setting mute state:', error);
  }
}

async function getOutputDeviceLinux() {
  try {
    const { stdout } = await execAsync('amixer');
    const match = stdout.match(/Simple mixer control '([^']+)'/);
    return match ? match[1] : 'Master';
  } catch (error) {
    console.error('Error getting output device:', error);
    return 'Master';
  }
}

// macOS volume control using osascript
async function getVolumeMac() {
  try {
    const { stdout } = await execAsync('osascript -e "output volume of (get volume settings)"');
    return parseInt(stdout.trim());
  } catch (error) {
    console.error('Error getting volume:', error);
    return 0;
  }
}

async function setVolumeMac(volume) {
  try {
    await execAsync(`osascript -e "set volume output volume ${volume}"`);
  } catch (error) {
    console.error('Error setting volume:', error);
  }
}

async function getMutedMac() {
  try {
    const { stdout } = await execAsync('osascript -e "output muted of (get volume settings)"');
    return stdout.trim() === 'true';
  } catch (error) {
    console.error('Error getting mute state:', error);
    return false;
  }
}

async function setMutedMac(muted) {
  try {
    await execAsync(`osascript -e "set volume ${muted ? 'with' : 'without'} output muted"`);
  } catch (error) {
    console.error('Error setting mute state:', error);
  }
}

async function getOutputDeviceMac() {
  try {
    const { stdout } = await execAsync('system_profiler SPAudioDataType | grep "Default Output Device" -A 1 | tail -n 1 | sed "s/.*: //"');
    return stdout.trim() || 'Built-in Output';
  } catch (error) {
    console.error('Error getting output device:', error);
    return 'Built-in Output';
  }
}

// Windows volume control using PowerShell
async function getVolumeWindows() {
  try {
    const { stdout } = await execAsync(
      'powershell -c "(New-Object -ComObject WScript.Shell).SendKeys([char]174); Start-Sleep -m 50; Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait(\'{ESC}\'); [Math]::Round([Audio]::Volume * 100)"'
    );
    return parseInt(stdout.trim());
  } catch (error) {
    console.error('Error getting volume:', error);
    return 0;
  }
}

async function setVolumeWindows(volume) {
  try {
    const script = `
      $wshShell = New-Object -ComObject WScript.Shell
      1..50 | ForEach-Object { $wshShell.SendKeys([char]174) }
      1..${volume} | ForEach-Object { $wshShell.SendKeys([char]175) }
    `;
    await execAsync(`powershell -c "${script.replace(/\n/g, ' ')}"`);
  } catch (error) {
    console.error('Error setting volume:', error);
  }
}

async function getMutedWindows() {
  try {
    const { stdout } = await execAsync(
      'powershell -c "Get-AudioDevice -PlaybackMute"'
    );
    return stdout.trim() === 'True';
  } catch (error) {
    console.error('Error getting mute state:', error);
    return false;
  }
}

async function setMutedWindows(muted) {
  try {
    await execAsync(`powershell -c "Set-AudioDevice -PlaybackMute ${muted}"`);
  } catch (error) {
    console.error('Error setting mute state:', error);
  }
}

async function getOutputDeviceWindows() {
  try {
    const { stdout } = await execAsync(
      'powershell -c "(Get-AudioDevice -Playback).Name"'
    );
    return stdout.trim() || 'Default';
  } catch (error) {
    console.error('Error getting output device:', error);
    return 'Default';
  }
}

// Platform-agnostic API
module.exports = {
  async getVolume() {
    switch (platform) {
      case 'linux':
        return await getVolumeLinux();
      case 'darwin':
        return await getVolumeMac();
      case 'win32':
        return await getVolumeWindows();
      default:
        throw new Error(`Unsupported platform: ${platform}`);
    }
  },

  async setVolume(volume) {
    const vol = Math.max(0, Math.min(100, volume));
    switch (platform) {
      case 'linux':
        await setVolumeLinux(vol);
        break;
      case 'darwin':
        await setVolumeMac(vol);
        break;
      case 'win32':
        await setVolumeWindows(vol);
        break;
      default:
        throw new Error(`Unsupported platform: ${platform}`);
    }
  },

  async getMuted() {
    switch (platform) {
      case 'linux':
        return await getMutedLinux();
      case 'darwin':
        return await getMutedMac();
      case 'win32':
        return await getMutedWindows();
      default:
        throw new Error(`Unsupported platform: ${platform}`);
    }
  },

  async setMuted(muted) {
    switch (platform) {
      case 'linux':
        await setMutedLinux(muted);
        break;
      case 'darwin':
        await setMutedMac(muted);
        break;
      case 'win32':
        await setMutedWindows(muted);
        break;
      default:
        throw new Error(`Unsupported platform: ${platform}`);
    }
  },

  async getOutputDevice() {
    switch (platform) {
      case 'linux':
        return await getOutputDeviceLinux();
      case 'darwin':
        return await getOutputDeviceMac();
      case 'win32':
        return await getOutputDeviceWindows();
      default:
        throw new Error(`Unsupported platform: ${platform}`);
    }
  }
};
VOLUMECTRL_EOF

echo -e "${GREEN}✓ Created CommonJS volumeController.js${NC}"

echo -e "${YELLOW}Step 4: Creating simplified package.json${NC}"
cat > package.json << 'PACKAGEJSON_EOF'
{
  "name": "remote-volume",
  "version": "1.1.0",
  "description": "Control system volume via WebSocket - Headless Edition",
  "main": "main.js",
  "scripts": {
    "start": "electron .",
    "build": "electron-builder --linux tar.gz",
    "build:all": "electron-builder -mwl"
  },
  "keywords": ["volume", "websocket", "remote", "headless"],
  "author": "Ultimate GmbH (Headless mod)",
  "license": "MIT",
  "dependencies": {
    "electron-store": "^8.1.0",
    "ws": "^8.13.0"
  },
  "devDependencies": {
    "electron": "^25.3.1",
    "electron-builder": "^24.6.3"
  },
  "build": {
    "appId": "com.ultimate.remotevolume.headless",
    "productName": "RemoteVolume",
    "files": [
      "main.js",
      "volumeController.js",
      "icon.png",
      "icon.ico",
      "menuicon.png"
    ],
    "linux": {
      "target": ["tar.gz"],
      "category": "Utility",
      "icon": "icon.png"
    },
    "mac": {
      "target": ["tar.gz"],
      "category": "public.app-category.utilities",
      "icon": "icon.png"
    },
    "win": {
      "target": ["portable"],
      "icon": "icon.ico"
    }
  }
}
PACKAGEJSON_EOF

echo -e "${GREEN}✓ Created simplified package.json${NC}"

echo -e "${YELLOW}Step 5: Cleaning old build artifacts${NC}"
rm -rf node_modules package-lock.json dist
echo -e "${GREEN}✓ Cleaned${NC}"

echo -e "${YELLOW}Step 6: Installing dependencies${NC}"
npm install --legacy-peer-deps

echo -e "${YELLOW}Step 7: Building application${NC}"
npm run build

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Your tarball is located at:"
ls -lh dist/*.tar.gz 2>/dev/null || echo "No tarball found"
echo ""
echo -e "${BLUE}Quick Install:${NC}"
echo "  tar -xzf dist/RemoteVolume-*.tar.gz -C ~/.local/share/"
echo "  ln -s ~/.local/share/remote-volume-*/remote-volume ~/.local/bin/remote-volume"
echo ""
echo -e "${BLUE}Run:${NC}"
echo "  remote-volume"
echo ""
echo -e "${BLUE}Test WebSocket:${NC}"
echo "  # Install wscat: npm install -g wscat"
echo "  wscat -c ws://localhost:8080"
echo "  > {\"action\":\"getState\"}"
echo ""
echo -e "${YELLOW}Original files backed up with .backup extension${NC}"
