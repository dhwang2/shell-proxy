# shell-proxy

Modular Bash toolkit for VPS proxy service deployment and management.

Current version: `v0.0.0`

## Installation

Execute directly on the VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/dhwang2/shell-proxy/main/app/bootstrap.sh | bash
```

## Common Commands

```bash
proxy menu
proxy start
proxy stop
proxy restart
proxy status
proxy log
sudo bash /etc/shell-proxy/self_update.sh repo
```

## Directory Structure

```text
app/
├── bootstrap.sh          ← Installation entry point
├── env.sh                ← Module manifest and managed file definitions
├── install.sh
├── management.sh
├── self_update.sh
├── watchdog.sh
├── systemd/              ← Service templates
└── modules/              ← Modules grouped by domain
    ├── core/
    ├── protocol/
    ├── routing/
    ├── subscription/
    ├── user/
    ├── network/
    ├── runtime/
    └── service/
```

## Runtime

- Root directory: `/etc/shell-proxy`
- Module manifest: `app/env.sh`
- Supported protocols: VLESS, TUIC, Trojan, AnyTLS, Shadowsocks 2022, Snell v5 + ShadowTLS v3

## License

[MIT](LICENSE)

