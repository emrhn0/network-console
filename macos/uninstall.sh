#!/usr/bin/env bash
# Network Console - macOS kaldirma
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.networkconsole.agent.plist"
APP_DIR="$HOME/Applications/NetworkConsole.app"

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
pkill -f "NetworkConsole/Resources/app.py" 2>/dev/null || true
pkill -f "NetworkConsole/Resources/ping-agent.py" 2>/dev/null || true
rm -rf "$APP_DIR"

echo "Network Console kaldirildi."
