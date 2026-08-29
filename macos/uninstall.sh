#!/usr/bin/env bash
# Network Console - macOS kaldirma
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.networkconsole.agent.plist"
APP_DIR="$HOME/Applications/NetworkConsole.app"

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
# Desen gercek yola uymali: .../NetworkConsole.app/Contents/Resources/...
pkill -f "NetworkConsole\.app/Contents/Resources/app\.py" 2>/dev/null || true
pkill -f "NetworkConsole\.app/Contents/Resources/ping-agent\.py" 2>/dev/null || true
sleep 1
pkill -9 -f "NetworkConsole\.app/Contents/Resources/ping-agent\.py" 2>/dev/null || true
rm -rf "$APP_DIR"

echo "Network Console kaldirildi."
