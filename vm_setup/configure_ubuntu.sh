#!/bin/bash

# Configure bash history
sudo echo 'export PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"' >> ~/.bashrc
sudo echo 'export HISTSIZE=10000' >> ~/.bashrc
sudo echo 'export HISTFILESIZE=10000' >> ~/.bashrc

### DEPENDENCIES

sudo apt install -y git python3 python3-dev python3-venv libaugeas-dev gcc nginx make gnupg pass

### Setup Docker credential helper with pass
sudo wget https://github.com/docker/docker-credential-helpers/releases/download/v0.9.4/docker-credential-pass-v0.9.4.linux-amd64 -O /usr/local/bin/docker-credential-pass
sudo chmod +x /usr/local/bin/docker-credential-pass

# Generate GPG key for pass
# TODO: In a production environment, you would want to protect this key with a passphrase and securely manage it.
#       The problem is that after the VM reboots, there is no way to enter the passphrase to unlock the key for use by the Docker credential helper.
#       For now, we are generating a key without a passphrase for simplicity.
gpg --batch --gen-key <<EOF
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Subkey-Type: ecdh
Subkey-Curve: cv25519
Name-Real: Docker Credentials
Name-Email: webmaster@gocongress.org
Expire-Date: 0
EOF

# Initialize pass with the generated GPG key
pass init $(gpg --list-secret-keys --keyid-format LONG | grep ^sec | awk '{print $2}' | cut -d/ -f2)

# Insert a dummy entry to confirm it's working (no passphrase needed)
echo "pass is initialized" | pass insert docker-credential-helpers/docker-pass-initialized-check

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
    test -f /etc/docker/config.json || cat <<'EOF' | sudo tee /etc/docker/config.json
{
  "credsStore": "pass",
  "credHelpers": {
    "ghcr.io": "pass",
    "docker.io": "pass"
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

echo "Setup complete!"
echo ""
echo "Login to GitHub Container Registry with your username and a personal access token with 'read:packages' scope:"
echo "Run the following command and enter your token when prompted:"
echo "docker login ghcr.io -u YOUR_USERNAME --password-stdin"
echo ""
echo "After logging in, you can test pulling an image from GHCR to verify that the credential helper is working:"
echo "docker pull ghcr.io/gocongress/prizes/api:main"
echo ""
