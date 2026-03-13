[Unit]
Description=Caddy Subscription Service
After=network.target network-online.target
Requires=network-online.target

[Service]
User=root
Group=root
Environment=XDG_DATA_HOME={{CADDY_XDG_DATA_HOME}}
Environment=XDG_CONFIG_HOME={{CADDY_XDG_CONFIG_HOME}}
ExecStart={{EXEC_START}}
ExecReload={{EXEC_RELOAD}}
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
ReadWritePaths={{WORK_DIR}}
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=append:{{LOG_DIR}}/caddy-sub.service.log
StandardError=append:{{LOG_DIR}}/caddy-sub.service.log

[Install]
WantedBy=multi-user.target
