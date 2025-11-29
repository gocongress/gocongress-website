#!/bin/bash

# Configure bash history
sudo echo 'export PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"' >> ~/.bashrc
sudo echo 'export HISTSIZE=10000' >> ~/.bashrc
sudo echo 'export HISTFILESIZE=10000' >> ~/.bashrc

### DEPENDENCIES

sudo apt install -y git python3 python3-dev python3-venv libaugeas-dev gcc nginx make

# Enable nginx
sudo systemctl enable --now nginx

# Configure Nginx
sudo cp ./nginx.conf.d/*.conf /etc/nginx/conf.d/
sudo nginx -t && sudo systemctl reload nginx

sudo cp ./systemd/*.service /etc/systemd/system/
sudo systemctl enable gocongress-wordpress.service
sudo systemctl enable gocongress-prizes.service

# Setup certbot:
if ! command -v certbot &>/dev/null; then
    sudo python3 -m venv /opt/certbot/
    sudo /opt/certbot/bin/pip install --upgrade pip
    sudo /opt/certbot/bin/pip install certbot certbot-nginx
    sudo ln -s /opt/certbot/bin/certbot /usr/bin/certbot
    sudo certbot --nginx --non-interactive --agree-tos -d gc2026.gocongress.org -m webmaster@gocongress.org
    sudo certbot --nginx --non-interactive --agree-tos -d prizes.gocongress.org -m webmaster@gocongress.org
    # job to automatically renew cert and trigger nginx reload when renewed:
    echo "0 0,12 * * * root /opt/certbot/bin/python -c 'import random; import time; time.sleep(random.random() * 3600)' && sudo certbot renew -q --deploy-hook 'systemctl reload nginx'" | sudo tee -a /etc/crontab > /dev/null
    # job to once a month upgrade certbot:
    echo "0 3 1 * * root /opt/certbot/bin/pip install --upgrade certbot certbot-nginx > /var/log/certbot_update.log 2>&1" | sudo tee -a /etc/crontab > /dev/null
    # Enable HTTP/2 in Certbot-generated config
    sudo sed -i 's/listen 443 ssl;/listen 443 ssl http2;/' /etc/nginx/conf.d/gc2026.gocongress.org.conf
    sudo sed -i 's/listen 443 ssl;/listen 443 ssl http2;/' /etc/nginx/conf.d/prizes.gocongress.org.conf
    sudo nginx -t && sudo systemctl reload nginx
fi

# Install/configure Docker
if ! command -v docker &>/dev/null; then
    sudo apt install -f -y docker.io docker-compose-v2
    sudo usermod -aG docker $USER
    sudo newgrp docker
    test -d /etc/docker || sudo mkdir -pv /etc/docker
    # configure docker logging to ensure logs do not growth without bound
    test -f /etc/docker/daemon.json || cat <<'EOF' | sudo tee /etc/docker/daemon.json
{
  "debug": false,
  "experimental": false,
  "exec-opts": ["native.cgroupdriver=systemd"],
  "userland-proxy": false,
  "live-restore": true,
  "log-level": "warn",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF
    # ensure service is enabled just in case:
    sudo systemctl enable --now docker.service
fi

# configure the firewall
sudo ufw allow 22 # allow SSH first
sudo ufw allow 80
sudo ufw allow 443
sudo ufw --force enable # enable firewall last non-interactively

# Setup local secrets store
sudo mkdir -pv /opt/secrets
sudo chown -R $USER:$USER /opt/secrets
sudo chmod 700 /opt/secrets
touch /opt/secrets/prizes.env.production
