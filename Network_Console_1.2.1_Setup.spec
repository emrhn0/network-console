# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['setup.py'],
    pathex=[],
    binaries=[],
    datas=[('c:/Users/Datnes/Tools/ag-konsolu/NetworkConsole.exe', '.'), ('c:/Users/Datnes/Tools/ag-konsolu/NetworkConsole-Agent.exe', '.'), ('c:/Users/Datnes/Tools/ag-konsolu/ag-konsolu.html', '.'), ('c:/Users/Datnes/Tools/ag-konsolu/network-console-icon.ico', '.')],
    hiddenimports=[],
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
    name='Network_Console_1.2.1_Setup',
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
    icon=['c:/Users/Datnes/Tools/ag-konsolu/network-console-icon.ico'],
)
