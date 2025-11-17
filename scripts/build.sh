#!/bin/bash
# This script automates building distributable artifacts with luapack

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_PATH="$SCRIPT_DIR/../tools"
FILE_NAME="luapack-linux-x86_64.zip"
DOWNLOAD_URL="https://github.com/00fast00/luapack/releases/download/v0.1.1/luapack-linux-x86_64.zip"

# echo "[1/4] Downloading luapack..."
# mkdir -p "$BASE_PATH"

# if command -v curl &> /dev/null; then
#     curl -L -o "$BASE_PATH/$FILE_NAME" "$DOWNLOAD_URL"
# elif command -v wget &> /dev/null; then
#     wget -O "$BASE_PATH/$FILE_NAME" "$DOWNLOAD_URL"
# else
#     echo "ERROR: Neither curl nor wget found. Please install one of them."
#     exit 1
# fi

# unzip -o "$BASE_PATH/$FILE_NAME" -d "$BASE_PATH"

# if [ $? -ne 0 ]; then
#     echo "ERROR: Luapack download or extraction failed"
#     exit 1
# fi

# Make luapack executable
chmod +x "$BASE_PATH/luapack"

echo "[2/4] Cleaning up old build artifacts..."
if [ -d "$SCRIPT_DIR/../dist" ]; then
    rm -rf "$SCRIPT_DIR/../dist"
fi

echo "[3/4] Bundling..."
cd "$SCRIPT_DIR/.."
"$BASE_PATH/luapack" bundle "src/raptor-panel/raptor-panel.lua" --config src/raptor-panel/luapack.toml
"$BASE_PATH/luapack" bundle "src/raptor-notifications/raptor-notifications.lua" --config src/raptor-notifications/luapack.toml

if [ $? -ne 0 ]; then
    echo "ERROR: Luapack bundling failed"
    exit 1
fi

echo "[4/4] Copying assets..."
mkdir -p "$SCRIPT_DIR/../dist/raptor-notifications"
mkdir -p "$SCRIPT_DIR/../dist/raptor-panel"

# Copy assets excluding .lua and .toml files
rsync -a --exclude='*.lua' --exclude='*.toml' "$SCRIPT_DIR/../src/raptor-notifications/" "$SCRIPT_DIR/../dist/raptor-notifications/" 2>/dev/null || true
rsync -a --exclude='*.lua' --exclude='*.toml' "$SCRIPT_DIR/../src/raptor-panel/" "$SCRIPT_DIR/../dist/raptor-panel/" 2>/dev/null || true

echo "Build completed successfully!"
