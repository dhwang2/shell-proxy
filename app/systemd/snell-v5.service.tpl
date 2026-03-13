[Unit]
Description=Snell shell-proxy Service
After=network.target

[Service]
ExecStart={{EXEC_START}}
Restart=on-failure
StandardOutput=append:{{LOG_DIR}}/snell-v5.service.log
StandardError=append:{{LOG_DIR}}/snell-v5.service.log

[Install]
WantedBy=multi-user.target
