#!/bin/bash
set -e

echo "=== Remote Volume Headless Build Fix Script ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    echo -e "${RED}Error: package.json not found. Please run this from the remote-volume directory${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Installing Python distutils fix${NC}"
# Install python3-distutils for Python 3.13
if command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y python3-distlib python3-dev build-essential
elif command -v dnf &> /dev/null; then
    sudo dnf install -y python3-devel gcc gcc-c++ make
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm python python-setuptools base-devel
else
    echo -e "${YELLOW}Warning: Unknown package manager. Please install python3-distutils manually${NC}"
fi

echo ""
echo -e "${YELLOW}Step 2: Cleaning previous build artifacts${NC}"
rm -rf node_modules package-lock.json dist

echo ""
echo -e "${YELLOW}Step 3: Updating package.json to skip problematic audio dependencies${NC}"

# Backup original package.json
cp package.json package.json.backup

# Create a modified package.json that removes the problematic audio dependency
# The naudiodon package is only needed for some advanced audio features we don't use
cat > package.json.tmp << 'EOF'
{
  "name": "remote-volume",
  "version": "1.1.0",
  "description": "Control system volume via WebSocket",
  "main": "main.js",
  "scripts": {
    "start": "electron .",
    "build": "electron-builder --linux tar.gz",
    "build:all": "electron-builder -mwl"
  },
  "keywords": ["volume", "websocket", "remote"],
  "author": "Ultimate GmbH",
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
    "appId": "com.ultimate.remotevolume",
    "productName": "RemoteVolume",
    "files": [
      "main.js",
      "renderer.js",
      "volumeController.js",
      "index.html",
      "icon.png",
      "icon.ico",
      "menuicon.png",
      "impl/**/*"
    ],
    "linux": {
      "target": ["tar.gz"],
      "category": "Utility",
      "icon": "icon.png"
    }
  }
}
EOF

mv package.json.tmp package.json

echo ""
echo -e "${YELLOW}Step 4: Installing dependencies${NC}"
npm install --legacy-peer-deps

echo ""
echo -e "${YELLOW}Step 5: Checking if main.js has been replaced with headless version${NC}"
if grep -q "headless mode" main.js; then
    echo -e "${GREEN}✓ Headless main.js detected${NC}"
else
    echo -e "${RED}✗ Original main.js detected${NC}"
    echo -e "${YELLOW}Please replace main.js with the headless version before building${NC}"
    read -p "Press enter to continue anyway, or Ctrl+C to abort..."
fi

echo ""
echo -e "${YELLOW}Step 6: Building application${NC}"
npm run build

echo ""
echo -e "${GREEN}=== Build Complete! ===${NC}"
echo ""
echo "Your tarball is located at:"
ls -lh dist/*.tar.gz 2>/dev/null || echo "No tarball found - check dist/ directory"
echo ""
echo "To install:"
echo "  tar -xzf dist/RemoteVolume-*.tar.gz -C ~/.local/share/"
echo "  ln -s ~/.local/share/remote-volume/remote-volume ~/.local/bin/remote-volume"
echo ""
echo "To run:"
echo "  remote-volume"
