[Unit]
Description=shell-proxy Watchdog
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart={{EXEC_START}}
Restart=always
RestartSec=3
StandardOutput=append:{{LOG_FILE}}
StandardError=append:{{LOG_FILE}}

[Install]
WantedBy=multi-user.target
