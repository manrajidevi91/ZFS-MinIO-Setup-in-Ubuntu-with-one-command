#!/bin/bash
set -e

#############################
# ZFS + MinIO Setup Section #
#############################

echo "🚀 Installing ZFS..."
apt update
apt install -y zfsutils-linux

LOOP_FILE="/var/zfs_pool.img"
LOOP_DEV="/dev/loop10"

# Check if the ZFS pool or loop file already exists
if [ -e "$LOOP_FILE" ] || zpool list | grep -q '^zpool1'; then
  echo "✅ ZFS pool or loop file already exists. Skipping creation step."

  # Attach loop device if not already attached
  if ! losetup | grep -q "$LOOP_FILE"; then
    echo "🔄 Reattaching loop file to $LOOP_DEV..."
    losetup $LOOP_DEV $LOOP_FILE
  fi

  # Import pool if not imported
  if ! zpool list | grep -q '^zpool1'; then
    echo "📦 Importing existing ZFS pool..."
    zpool import -d /dev zpool1
  fi
else
  echo "🔍 Calculating free space on root filesystem..."
  free_kb=$(df --output=avail / | tail -1 | tr -d ' ')
  free_bytes=$((free_kb * 1024))
  margin=1073741824

  if [ $free_bytes -le $margin ]; then
    echo "❌ Not enough free space available on / to create the loop file."
    exit 1
  fi

  loop_size=$((free_bytes - margin))
  echo "✅ Free space: $free_bytes bytes. Creating loop file of size $loop_size bytes."

  fallocate -l $loop_size $LOOP_FILE
  losetup $LOOP_DEV $LOOP_FILE

  echo "📦 Creating ZFS Pool (zpool1) on $LOOP_DEV..."
  zpool create -f zpool1 "$LOOP_DEV"

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
# Persisting ZFS Pool After Reboot     #
#########################################

echo ""
echo "🔧 Creating systemd service to reattach loop device and import ZFS pool..."
cat <<EOF >/etc/systemd/system/loop-zpool-import.service
[Unit]
Description=Reattach loop device and import ZFS pool
DefaultDependencies=no
Before=zfs-import.target
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/sbin/losetup /dev/loop10 /var/zfs_pool.img
ExecStartPost=/sbin/zpool import -d /dev zpool1
RemainAfterExit=yes

[Install]
WantedBy=zfs-import.target
EOF

systemctl daemon-reload
systemctl enable loop-zpool-import.service

# Save ZFS cache
zpool set cachefile=/etc/zfs/zpool.cache zpool1
systemctl restart zfs-import-cache.service

echo "✅ 'loop-zpool-import' service created and enabled."

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
echo "🔎 To check the loop file: losetup -a"
echo "✅ Setup complete. Access MinIO at: https://$DOMAIN"
