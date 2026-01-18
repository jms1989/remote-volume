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
