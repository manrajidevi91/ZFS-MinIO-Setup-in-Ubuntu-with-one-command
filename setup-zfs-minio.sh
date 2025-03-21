#!/bin/bash
set -e

#############################
# ZFS + MinIO Setup Section #
#############################

echo "🚀 Installing ZFS..."
apt update
apt install -y zfsutils-linux

echo "🔍 Calculating free space on root filesystem..."
# Get available space (in KB) on /
free_kb=$(df --output=avail / | tail -1 | tr -d ' ')
free_bytes=$((free_kb * 1024))

# Define a safety margin of 1GB (in bytes)
margin=1073741824

if [ $free_bytes -le $margin ]; then
  echo "❌ Not enough free space available on / to create the loop file."
  exit 1
fi

# Calculate the size for the loop file (all free space minus margin)
loop_size=$((free_bytes - margin))
echo "✅ Free space: $free_bytes bytes. Creating loop file of size $loop_size bytes (leaving a 1GB margin)."

# Define the loop file location
LOOP_FILE="/var/zfs_pool.img"

# Create the loop file (sparse file)
fallocate -l $loop_size $LOOP_FILE

# Attach the loop file to a loop device
LOOP_DEV=$(losetup --find --show $LOOP_FILE)
echo "✅ Using loop device: $LOOP_DEV"

echo "📦 Creating ZFS Pool (zpool1) on $LOOP_DEV..."
zpool create -f zpool1 "$LOOP_DEV"

echo "📁 Creating ZFS Dataset for MinIO..."
zfs create zpool1/minio

echo "📂 Mounting at /mnt/minio..."
mkdir -p /mnt/minio
zfs set mountpoint=/mnt/minio zpool1/minio

echo "🚀 Installing MinIO Server..."
# Create a dedicated user for MinIO if it doesn't exist
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
echo "➡️  MinIO Console is running on port 9001 (locally: http://127.0.0.1:9001)"
echo "➡️  MinIO API is running on port 9000 (locally: http://127.0.0.1:9000)"


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
echo "➡️  Access your MinIO Console at: https://$DOMAIN"
echo ""
echo "🔎 To check the loop file details, run: losetup -a"
