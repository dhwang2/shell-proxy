# shell-proxy

Bash production line — a collection of VPS proxy management scripts.

Current official version: `v0.0.0`

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
shell-proxy/
├── app/                      ← Application source code
│   ├── bootstrap.sh          ← Installation entry point
│   ├── env.sh                ← Module manifest and managed file definitions
│   ├── install.sh
│   ├── management.sh
│   ├── self_update.sh
│   ├── watchdog.sh
│   ├── systemd/              ← Service templates
│   └── modules/              ← Modules grouped by domain
│       ├── core/
│       ├── protocol/
│       ├── routing/
│       ├── subscription/
│       ├── user/
│       ├── network/
│       ├── runtime/
│       └── service/
└── docs/                     ← Documentation
```

## Runtime

- Running root directory: `/etc/shell-proxy`
- Core manifest and managed file definitions: `app/env.sh`

