#!/bin/bash
set -e

#############################
# ZFS + MinIO Setup Section #
#############################

echo "🚀 Installing ZFS..."
apt update
apt install -y zfsutils-linux

ZFS_DEVICE="/dev/vda"
echo "📦 Selected disk for ZFS pool: $ZFS_DEVICE"

# Create ZFS pool
if zpool list | grep -q '^zpool1'; then
  echo "✅ ZFS pool 'zpool1' already exists. Skipping creation."
else
  echo "📦 Creating ZFS Pool (zpool1) on $ZFS_DEVICE..."
  zpool create -f zpool1 "$ZFS_DEVICE"
  echo "📁 Creating ZFS Dataset for MinIO..."
  zfs create zpool1/minio
fi

echo "📂 Mounting at /mnt/minio..."
mkdir -p /mnt/minio
zfs set mountpoint=/mnt/minio zpool1/minio

#############################
# MinIO Installation       #
#############################

echo "🚀 Installing MinIO Server..."
useradd -r minio-user 2>/dev/null || true
mkdir -p /mnt/minio/{data,config}
chown -R minio-user:minio-user /mnt/minio

if [ ! -f /usr/local/bin/minio ]; then
  wget https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
  chmod +x /usr/local/bin/minio
else
  echo "✅ MinIO binary already exists, skipping download."
fi

echo "🔧 Creating MinIO systemd service..."
cat <<EOF >/etc/systemd/system/minio.service
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
User=minio-user
Group=minio-user
ExecStart=/usr/local/bin/minio server /mnt/minio/data --console-address ":9001"
Environment="MINIO_ROOT_USER=admin"
Environment="MINIO_ROOT_PASSWORD=adminpassword"
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "📡 Enabling and starting MinIO..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now minio

echo "✅ MinIO setup complete!"
echo "➡️  MinIO Console: http://127.0.0.1:9001"
echo "➡️  MinIO API: http://127.0.0.1:9000"

#############################
# DuckDNS Configuration     #
#############################

echo ""
echo "🔧 DuckDNS Configuration..."

# If command-line arguments for DuckDNS token and subdomain are provided, use them.
if [[ -n "$1" && -n "$2" ]]; then
  DUCKDNS_TOKEN="$1"
  DUCKDNS_SUBDOMAIN="$2"
  USE_DUCKDNS="y"
  EMAIL_ARG="$3"  # optional email argument
else
  read -p "Do you want to use DuckDNS for dynamic DNS? (y/n): " USE_DUCKDNS
fi

if [[ "$USE_DUCKDNS" =~ ^[Yy]$ ]]; then
  # If not provided via arguments, prompt for the token.
  if [[ -z "$DUCKDNS_TOKEN" ]]; then
    read -p "Enter your DuckDNS API token: " DUCKDNS_TOKEN
  fi

  # If not provided via arguments, prompt for the subdomain.
  if [[ -z "$DUCKDNS_SUBDOMAIN" ]]; then
    read -p "Enter your DuckDNS subdomain (without .duckdns.org): " DUCKDNS_SUBDOMAIN
  fi

  DOMAIN="${DUCKDNS_SUBDOMAIN}.duckdns.org"

  # For email, use the provided argument if available; otherwise prompt.
  if [[ -z "$EMAIL_ARG" ]]; then
    read -p "Enter your email for SSL certificate registration: " EMAIL
  else
    EMAIL="$EMAIL_ARG"
  fi

  DUCKDNS_SCRIPT="/usr/local/bin/update-duckdns.sh"
  cat <<EOF > "$DUCKDNS_SCRIPT"
#!/bin/bash
curl -k "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip="
EOF
  chmod +x "$DUCKDNS_SCRIPT"

  echo "✅ DuckDNS update script created at $DUCKDNS_SCRIPT."
  echo "🚀 Setting up cron job to update DuckDNS every 10 minutes..."
  (crontab -l 2>/dev/null; echo "*/10 * * * * $DUCKDNS_SCRIPT >/dev/null 2>&1") | crontab -
  echo "✅ DuckDNS cron job set."
  echo "✅ DuckDNS configuration completed."
  echo "  Domain: $DOMAIN"
  echo "  Email: $EMAIL"
else
  echo "✅ DuckDNS configuration skipped."
  # Prompt for domain manually if DuckDNS is not used.
  while true; do
    read -p "Enter your domain name for MinIO (e.g. minio.example.com): " DOMAIN
    if [[ -n "$DOMAIN" ]]; then
      break
    fi
    echo "Error: Domain cannot be empty. Please provide a valid domain."
  done
  read -p "Enter your email for SSL certificate registration: " EMAIL
fi

#############################
# Exposing MinIO with Nginx and SSL    #
#############################

echo ""
echo "🚀 Installing Nginx and Certbot for SSL..."
apt install -y nginx certbot python3-certbot-nginx

echo "🚀 Configuring Nginx reverse proxy for MinIO Console..."
NGINX_CONF="/etc/nginx/sites-available/minio.conf"
cat <<EOF > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:9001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf $NGINX_CONF /etc/nginx/sites-enabled/minio.conf
nginx -t && systemctl reload nginx

echo "🚀 Obtaining SSL certificate with Certbot..."
certbot --nginx --redirect --agree-tos --non-interactive -d "$DOMAIN" -m "$EMAIL"

echo "✅ SSL setup complete."
echo "➡️  Access MinIO at: https://$DOMAIN"
