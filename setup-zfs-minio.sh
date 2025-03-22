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

#########################################
# DuckDNS (Dynamic DNS) Configuration  #
#########################################

echo ""
read -p "Do you want to use DuckDNS for dynamic DNS? (y/n): " USE_DUCKDNS
if [ "$USE_DUCKDNS" = "y" ] || [ "$USE_DUCKDNS" = "Y" ]; then
    read -p "Enter your DuckDNS API token: " DUCKDNS_TOKEN
    read -p "Enter your DuckDNS subdomain (without .duckdns.org): " DUCKDNS_SUBDOMAIN
    DOMAIN="$DUCKDNS_SUBDOMAIN.duckdns.org"
    DUCKDNS_SCRIPT="/usr/local/bin/update-duckdns.sh"
    cat <<EOF > $DUCKDNS_SCRIPT
#!/bin/bash
curl -k "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip="
EOF
    chmod +x $DUCKDNS_SCRIPT
    echo "✅ DuckDNS update script created at $DUCKDNS_SCRIPT."
    echo "🚀 Setting up cron job to update DuckDNS every 10 minutes..."
    (crontab -l 2>/dev/null; echo "*/10 * * * * $DUCKDNS_SCRIPT >/dev/null 2>&1") | crontab -
    echo "✅ DuckDNS cron job set."
else
    echo "✅ DuckDNS configuration skipped."
    read -p "Enter your domain name for MinIO (e.g. minio.example.com): " DOMAIN
fi

read -p "Enter your email for SSL certificate registration: " EMAIL

#########################################
# Exposing MinIO with Nginx and SSL    #
#########################################

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
certbot --nginx --redirect --agree-tos --non-interactive -d $DOMAIN -m $EMAIL

echo "✅ SSL setup complete."
echo "➡️  Access MinIO at: https://$DOMAIN"
