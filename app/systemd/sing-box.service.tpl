[Unit]
Description=Sing-box Service
After=network.target nss-lookup.target

[Service]
ExecStart={{EXEC_START}}
Restart=on-failure
LimitNOFILE=infinity
StandardOutput=append:{{LOG_DIR}}/sing-box.service.log
StandardError=append:{{LOG_DIR}}/sing-box.service.log

[Install]
WantedBy=multi-user.target
