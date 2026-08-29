#!/usr/bin/env bash
# Network Console - macOS kurulumu
#
# Bu betik ~/Applications/NetworkConsole.app adinda gercek bir macOS
# uygulamasi olusturur (pywebview ile native pencere, Dock'ta kendi
# ikonuyla gorunur) ve ajanin giriste otomatik baslamasi icin bir
# LaunchAgent kaydeder.
#
# Kullanim: bu klasordeki (macos/) install.sh dosyasini Terminal'den
# calistir:
#   chmod +x install.sh && ./install.sh
#
# Gereksinim: Python 3 (macOS'ta genelde onceden kurulu, yoksa
# https://www.python.org/downloads/macos/ adresinden kurulabilir).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$HOME/Applications/NetworkConsole.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENTS/com.networkconsole.agent.plist"

echo "[1/6] Onceki surum kapatiliyor..."
pkill -f "NetworkConsole/Resources/app.py" 2>/dev/null || true
pkill -f "NetworkConsole/Resources/ping-agent.py" 2>/dev/null || true
launchctl unload "$PLIST" 2>/dev/null || true

echo "[2/6] Uygulama klasoru olusturuluyor -> $APP_DIR"
# Var olan .venv'i koru: yeniden kurulumda pywebview/pyobjc'yi bastan
# indirmek bir dakikayi buluyor ve ilk acilis yine yavas oluyor.
VENV_KEEP=""
if [ -d "$RES_DIR/.venv" ]; then
  VENV_KEEP="$(mktemp -d)/venv"
  mv "$RES_DIR/.venv" "$VENV_KEEP"
  echo "      (mevcut Python ortami korunuyor)"
fi
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
if [ -n "$VENV_KEEP" ]; then
  mv "$VENV_KEEP" "$RES_DIR/.venv"
fi

echo "[3/6] Dosyalar kopyalaniyor..."
cp "$REPO_DIR/app.py" "$RES_DIR/app.py"
cp "$REPO_DIR/ping-agent.py" "$RES_DIR/ping-agent.py"
cp "$REPO_DIR/ag-konsolu.html" "$RES_DIR/ag-konsolu.html"
# vt-key.txt istege bagli. "set -e" altinda ciplak "[ -f x ] && cp" kalibi,
# dosya yoksa listeyi basarisiz sayip kurulumu burada sessizce durdurur.
if [ -f "$REPO_DIR/vt-key.txt" ]; then
  cp "$REPO_DIR/vt-key.txt" "$RES_DIR/vt-key.txt"
fi
cp "$REPO_DIR/network-console-icon.png" "$RES_DIR/network-console-icon.png"

echo "[4/6] Simge (.icns) olusturuluyor..."
ICONSET="$RES_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC_PNG="$RES_DIR/network-console-icon.png"
for size in 16 32 64 128 256 512; do
  sips -z "$size" "$size" "$SRC_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$SRC_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"
rm -rf "$ICONSET"

echo "[5/6] Baslatici script ve Info.plist yaziliyor..."
cat > "$MACOS_DIR/NetworkConsole" <<'LAUNCHER'
#!/usr/bin/env bash
# Bu betik .app'in giris noktasidir. Finder'dan calistirildiginda hicbir
# terminal gorunmez, bu yuzden ilerleme ve hatalar hem bir kayit dosyasina
# hem de macOS bildirimi/uyarisi olarak kullaniciya bildirilir. Aksi halde
# ilk acilisin uzun surmesi "ikon zipladi, uygulama acilmadi" gibi gorunur.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../Resources" && pwd)"
VENV="$HERE/.venv"
LOG="$HOME/Library/Logs/NetworkConsole-launch.log"
mkdir -p "$(dirname "$LOG")"

log()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }
note()  { osascript -e "display notification \"$1\" with title \"Network Console\"" >/dev/null 2>&1 || true; }
fail()  {
  log "HATA: $1"
  osascript -e "display alert \"Network Console\" message \"$1

Ayrinti: $LOG\"" >/dev/null 2>&1 || true
  exit 1
}

log "baslatiliyor"

if [ ! -x "$VENV/bin/python3" ]; then
  PY=$(command -v python3 || true)
  if [ -z "$PY" ]; then
    fail "Python 3 bulunamadi. https://www.python.org/downloads/macos/ adresinden kurup tekrar deneyin."
  fi
  note "Ilk kurulum yapiliyor, bu bir dakika surebilir..."
  log "venv olusturuluyor: $PY"
  "$PY" -m venv "$VENV"           >>"$LOG" 2>&1 || fail "Python ortami olusturulamadi."
  "$VENV/bin/pip" install --upgrade pip >>"$LOG" 2>&1 || true
  log "pywebview + pyobjc kuruluyor"
  "$VENV/bin/pip" install pywebview pyobjc >>"$LOG" 2>&1 \
    || fail "Gerekli bilesenler kurulamadi. Internet baglantinizi kontrol edip tekrar deneyin."
  note "Kurulum tamam, uygulama aciliyor."
  log "kurulum tamamlandi"
fi

log "app.py calistiriliyor"
exec "$VENV/bin/python3" "$HERE/app.py" >>"$LOG" 2>&1
LAUNCHER
chmod +x "$MACOS_DIR/NetworkConsole"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Network Console</string>
  <key>CFBundleDisplayName</key><string>Network Console</string>
  <key>CFBundleIdentifier</key><string>com.networkconsole.app</string>
  <key>CFBundleVersion</key><string>1.4.1</string>
  <key>CFBundleShortVersionString</key><string>1.4.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>NetworkConsole</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "[6/6] Ajan giriste otomatik baslayacak sekilde ayarlaniyor..."
mkdir -p "$LAUNCH_AGENTS"
cat > "$PLIST" <<AGENTPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.networkconsole.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>$RES_DIR/.venv/bin/python3</string>
    <string>$RES_DIR/ping-agent.py</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>StandardOutPath</key><string>/tmp/networkconsole-agent.log</string>
  <key>StandardErrorPath</key><string>/tmp/networkconsole-agent.log</string>
</dict>
</plist>
AGENTPLIST

echo ""
echo "Kurulum tamamlandi."
echo "Uygulama: $APP_DIR"
echo "Ilk acilista pywebview/pyobjc kurulacagi icin birkac saniye surebilir."
echo "Finder'dan Applications > NetworkConsole.app'e cift tiklayarak baslatabilirsin."
echo "Ajani hemen simdi de baslatmak icin: launchctl load $PLIST"
