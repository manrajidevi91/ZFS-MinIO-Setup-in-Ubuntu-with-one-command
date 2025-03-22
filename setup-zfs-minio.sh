#!/bin/bash
set -e

#############################
# ZFS + MinIO Setup Section #
#############################

DUCKDNS_TOKEN="$1"
DUCKDNS_SUBDOMAIN="$2"
EMAIL="$3"

if [[ -z "$DUCKDNS_TOKEN" || -z "$DUCKDNS_SUBDOMAIN" || -z "$EMAIL" ]]; then
  echo "❌ Error: Please provide all three arguments - DuckDNS token, subdomain, and email."
  echo "Usage: bash setup.sh <DUCKDNS_TOKEN> <SUBDOMAIN> <EMAIL>"
  exit 1
fi

DOMAIN="$DUCKDNS_SUBDOMAIN.duckdns.org"

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

#########################################
# DuckDNS (Dynamic DNS) Configuration  #
#########################################

echo ""
echo "🔧 Configuring DuckDNS with: $DOMAIN"
mkdir -p /opt/duckdns
DUCKDNS_SCRIPT="/opt/duckdns/duck.sh"
echo "echo url=\"https://www.duckdns.org/update?domains=$DUCKDNS_SUBDOMAIN&token=$DUCKDNS_TOKEN&ip=\" | curl -k -o /opt/duckdns/duck.log -K -" > "$DUCKDNS_SCRIPT"
chmod 700 "$DUCKDNS_SCRIPT"

# Test DuckDNS script once manually
bash "$DUCKDNS_SCRIPT"

# Set cron job
crontab -l 2>/dev/null | grep -v "$DUCKDNS_SCRIPT" > /tmp/cron.tmp || true
echo "*/5 * * * * $DUCKDNS_SCRIPT >/dev/null 2>&1" >> /tmp/cron.tmp
crontab /tmp/cron.tmp
rm /tmp/cron.tmp

echo "✅ DuckDNS update script created at $DUCKDNS_SCRIPT."
echo "✅ Cron job set to run every 5 minutes."

#########################################
# Exposing MinIO with Nginx and SSL    #
#########################################

echo ""
echo "🚀 Installing Nginx and Certbot for SSL..."
apt install -y nginx certbot python3-certbot-nginx
systemctl enable nginx
systemctl start nginx

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
certbot --nginx --redirect --agree-tos --non-interactive -d $DOMAIN -m $EMAIL

echo "✅ SSL setup complete."
echo "➡️  Access MinIO at: https://$DOMAIN"
