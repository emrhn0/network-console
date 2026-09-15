# Network Console

Native desktop network diagnostics toolkit, built with Flutter: ping, traceroute, DNS, TLS
certificates, HTTP checks, port/IP scanning, subnet math, VirusTotal URL reputation, plus
SSH/SNMP probes and Wake-on-LAN — all in one console.

The UI (`flutter_app/`) talks to a small local measurement agent (`ping-agent.py`) over
plain HTTP on `127.0.0.1`.

- Latest release (installer + portable zip, Windows and macOS): see [Releases](../../releases/latest).
- Source: [`flutter_app/`](flutter_app) (UI) + [`ping-agent.py`](ping-agent.py) (backend agent).

## Installing on macOS

Unzip the release, drag `network_console_app.app` into **Applications**, and double-click
it. The first launch is blocked with "Apple cannot check it for malicious software" — the
app is code-signed, but notarizing it requires a paid Apple Developer account. Open
**System Settings > Privacy & Security**, scroll to the Security section, and click
**Open Anyway**. That is a one-time step; afterwards it launches normally.

No Terminal commands are needed. If a build up to 2.7.7 told you the app "is damaged and
can't be opened", that was a packaging bug — the agent binary was copied into the bundle
after signing, breaking the code-signature seal — fixed in 2.7.8.
