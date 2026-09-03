# Network Console

Local network diagnostics toolkit — ping, traceroute, DNS, TLS certificates, HTTP checks,
port/IP scanning, subnet math and VirusTotal URL reputation, all in one desktop app.

**This branch (`flutter-v2`, the repo default) is the current version: a native Flutter
desktop app** (`flutter_app/`). It talks to the same local measurement agent
(`ping-agent.py`) the previous version used, over plain HTTP on `127.0.0.1`.

- Latest release (installer + portable zip): see [Releases](../../releases/latest).
- Source: [`flutter_app/`](flutter_app) (UI) + [`ping-agent.py`](ping-agent.py) (backend agent).

## Previous version (1.5.x, HTML/pywebview)

The original HTML/WebView2-based app is still available and untouched:

- Branch: [`master`](../../tree/master) — build it yourself from source, or check that
  branch's own release workflow for the latest packaged installer.

It's kept around on purpose in case the Flutter rewrite doesn't work out for you — nothing
from it was deleted or modified.
