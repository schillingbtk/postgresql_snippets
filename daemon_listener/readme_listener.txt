sudo systemctl daemon-reload
sudo systemctl enable db_listener.service
sudo systemctl start db_listener.service
sudo systemctl status db_listener.service

