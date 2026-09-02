# -*- mode: python ; coding: utf-8 -*-
import sys

# pystray._win32 sadece Windows'ta var - macOS/Linux derlemesinde PyInstaller
# bu modulu bulmaya calisip patlar, o yuzden platforma gore kosullu.
_hidden = ['pystray._win32'] if sys.platform.startswith('win') else []
_icon = ['network-console-icon.ico'] if sys.platform.startswith('win') else None

a = Analysis(
    ['ping-agent.py'],
    pathex=[],
    binaries=[],
    datas=[('network-console-icon.ico', '.')],
    hiddenimports=_hidden,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='NetworkConsole-Agent',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=_icon,
)
