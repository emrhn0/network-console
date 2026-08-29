#!/usr/bin/env bash
# Network Console - kendi kendine yeten macOS uygulamasi + .dmg uretir
#
# install.sh'ten farki: install.sh makinede bir venv kurup kaynak dosyalari
# kopyalar (gelistirme icin pratik). Bu betik ise PyInstaller ile Python'u
# ve tum bagimliliklari ICINE gomulmus bir .app uretir; kullanicinin Python
# kurmasina, repoyu klonlamasina gerek kalmaz. CI de bunu calistirir.
#
# Kullanim:  bash macos/build-app.sh
# Cikti   :  dist/NetworkConsole.app  ve  dist/Network_Console_<surum>_macOS.dmg

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

VERSION="${1:-$(sed -n 's/^VERSION = "\(.*\)"/\1/p' setup.py)}"
[ -n "$VERSION" ] || { echo "Surum belirlenemedi."; exit 1; }
echo "== Network Console $VERSION - macOS paketi =="

BUILD="$REPO_DIR/build/macos"
DIST="$REPO_DIR/dist"
APP="$DIST/NetworkConsole.app"
rm -rf "$BUILD" "$APP" "$DIST"/*.dmg
mkdir -p "$BUILD" "$DIST"

# --- 1) simge (.icns) ---------------------------------------------------
echo "[1/5] Simge olusturuluyor..."
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512; do
  sips -z "$size" "$size" network-console-icon.png \
       --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  d=$((size * 2))
  sips -z "$d" "$d" network-console-icon.png \
       --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"

# --- 2) ajan (konsol ikilisi) -------------------------------------------
# app.py bunu "NetworkConsole-Agent" adiyla, kendi yaninda arar.
echo "[2/5] Ajan derleniyor..."
pyinstaller --noconfirm --clean --onefile \
  --name NetworkConsole-Agent \
  --distpath "$BUILD/agent" --workpath "$BUILD/work" --specpath "$BUILD" \
  ping-agent.py >/dev/null

# --- 3) uygulama penceresi (.app) ---------------------------------------
echo "[3/5] Uygulama derleniyor..."
pyinstaller --noconfirm --clean --windowed \
  --name NetworkConsole \
  --icon "$BUILD/AppIcon.icns" \
  --osx-bundle-identifier com.networkconsole.app \
  --distpath "$DIST" --workpath "$BUILD/work" --specpath "$BUILD" \
  app.py >/dev/null

# --- 4) veri dosyalarini bundle'a koy -----------------------------------
# Hem app.py hem ping-agent.py, donmus halde dosyalari
# os.path.dirname(sys.executable) yaninda arar; orasi Contents/MacOS.
echo "[4/5] Kaynaklar bundle'a kopyalaniyor..."
MACOS_DIR="$APP/Contents/MacOS"
cp "$BUILD/agent/NetworkConsole-Agent" "$MACOS_DIR/NetworkConsole-Agent"
chmod +x "$MACOS_DIR/NetworkConsole-Agent"
cp ag-konsolu.html            "$MACOS_DIR/ag-konsolu.html"
cp network-console-icon.png   "$MACOS_DIR/network-console-icon.png"
if [ -f vt-key.txt ]; then cp vt-key.txt "$MACOS_DIR/vt-key.txt"; fi

# Info.plist'e surum ve "arka plan uygulamasi degil" bilgisini yaz
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Network Console" "$PLIST" 2>/dev/null || true

# Kopyalanan dosyalarin genisletilmis oznitelikleri codesign'i
# "resource fork, Finder information, or similar detritus not allowed"
# hatasiyla dusuruyor; imzalamadan once temizle.
xattr -cr "$APP" 2>/dev/null || true

# Imzasiz bir .app'i Gatekeeper karantinaya alir. Kendi kendini imzalayan
# (ad-hoc) imza, en azindan "bozuk" hatasi yerine normal uyariyi verdirir.
if codesign --force --deep --sign - "$APP" 2>/dev/null; then
  echo "      ad-hoc imza tamam"
else
  echo "      (ad-hoc imza atlandi)"
fi

# --- 5) .dmg ------------------------------------------------------------
echo "[5/5] .dmg paketleniyor..."
DMG="$DIST/Network_Console_${VERSION}_macOS.dmg"
STAGE="$BUILD/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"        # surukle-birak kurulum
hdiutil create -volname "Network Console" -srcfolder "$STAGE" \
        -ov -format UDZO "$DMG" >/dev/null

echo ""
echo "Bitti."
echo "  Uygulama : $APP"
echo "  Paket    : $DMG"
