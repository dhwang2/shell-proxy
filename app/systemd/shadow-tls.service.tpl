[Unit]
Description=Shadow-TLS Service
After=network.target

[Service]
ExecStart={{EXEC_START}}
Restart=on-failure
LimitNOFILE=infinity
StandardOutput=append:{{LOG_FILE}}
StandardError=append:{{LOG_FILE}}

[Install]
WantedBy=multi-user.target
