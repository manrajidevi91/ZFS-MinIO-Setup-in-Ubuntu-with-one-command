#!/bin/bash
set -e

#############################
# ZFS + MinIO Setup Section #
#############################

echo "🚀 Installing ZFS..."
apt update
apt install -y zfsutils-linux

echo "🔍 Available partitions:"
mapfile -t PARTS < <(lsblk -dpno NAME,SIZE,TYPE,MOUNTPOINT | grep "part")

if [ ${#PARTS[@]} -eq 0 ]; then
  echo "❌ No usable partitions found. Exiting."
  exit 1
fi

for i in "${!PARTS[@]}"; do
    echo "$((i+1)). ${PARTS[$i]}"
done

read -p "📦 Enter the number of the partition to use for ZFS pool (⚠️ will ERASE data): " PART_INDEX

# Validate input
if ! [[ "$PART_INDEX" =~ ^[0-9]+$ ]] || [ "$PART_INDEX" -lt 1 ] || [ "$PART_INDEX" -gt "${#PARTS[@]}" ]; then
    echo "❌ Invalid selection. Exiting."
    exit 1
fi

PART_INDEX=$((PART_INDEX - 1))
SELECTED_LINE="${PARTS[$PART_INDEX]}"
ZFS_DEVICE=$(echo "$SELECTED_LINE" | awk '{print $1}')
MOUNTPOINT=$(echo "$SELECTED_LINE" | awk '{print $4}')

if [ "$MOUNTPOINT" != "" ]; then
  echo "⚠️ WARNING: The selected partition ($ZFS_DEVICE) is mounted on $MOUNTPOINT."
  read -p "❌ This will ERASE your current system. Are you sure? (type YES to continue): " CONFIRM
  if [ "$CONFIRM" != "YES" ]; then
    echo "❌ Operation cancelled."
    exit 1
  fi
fi

# Check if the pool already exists
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

echo "🚀 Installing MinIO Server..."
useradd -r minio-user || true
mkdir -p /mnt/minio/{data,config}
chown -R minio-user:minio-user /mnt/minio

wget https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
chmod +x /usr/local/bin/minio

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
# Exposing MinIO with Nginx and SSL    #
#########################################

echo ""
echo "🚀 Installing Nginx and Certbot for SSL..."
apt install -y nginx certbot python3-certbot-nginx

echo "🚀 Configuring Nginx reverse proxy for MinIO Console..."
read -p "Enter your domain name for MinIO (e.g. minio.example.com): " DOMAIN
read -p "Enter your email for SSL certificate registration: " EMAIL

NGINX_CONF="/etc/nginx/sites-available/minio.conf"
cat <<EOF > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

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
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

echo "✅ SSL setup complete."
echo "➡️  Access MinIO at: https://$DOMAIN"

#########################################
# DuckDNS (Dynamic DNS) Configuration  #
#########################################

echo ""
read -p "Do you want to use DuckDNS for dynamic DNS? (y/n): " USE_DUCKDNS
if [ "$USE_DUCKDNS" = "y" ] || [ "$USE_DUCKDNS" = "Y" ]; then
    read -p "Enter your DuckDNS API token: " DUCKDNS_TOKEN
    read -p "Enter your DuckDNS subdomain (without .duckdns.org): " DUCKDNS_SUBDOMAIN
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
fi

echo ""
echo "✅ Setup complete. Access MinIO at: https://$DOMAIN"
