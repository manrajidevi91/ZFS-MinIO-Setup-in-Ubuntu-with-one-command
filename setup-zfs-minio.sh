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

# Create DuckDNS directory in home
mkdir -p ~/duckdns
DUCKDNS_SCRIPT=~/duckdns/duck.sh

# Create the update script with proper variable interpolation
cat << 'EOF' > "$DUCKDNS_SCRIPT"
#!/bin/bash
DUCKDNS_TOKEN="$1"
DUCKDNS_SUBDOMAIN="$2"
echo url="https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip=" | curl -k -o ~/duckdns/duck.log -K -
EOF

# Make the script executable
chmod 700 "$DUCKDNS_SCRIPT"

# Test DuckDNS script once manually
bash "$DUCKDNS_SCRIPT" "$DUCKDNS_TOKEN" "$DUCKDNS_SUBDOMAIN"

# Set up cron job
(crontab -l 2>/dev/null | grep -v "$DUCKDNS_SCRIPT"; echo "*/5 * * * * $DUCKDNS_SCRIPT '$DUCKDNS_TOKEN' '$DUCKDNS_SUBDOMAIN' >/dev/null 2>&1") | crontab -

echo "✅ DuckDNS update script created at $DUCKDNS_SCRIPT"
echo "✅ Cron job set to run every 5 minutes"

#########################################
# Exposing MinIO with Nginx and SSL    #
#########################################

echo ""
echo "🚀 Installing Nginx and Certbot for SSL..."
apt install -y nginx certbot python3-certbot-nginx
systemctl enable nginx

# Create webroot directory for ACME challenges
mkdir -p /var/www/html/.well-known/acme-challenge
chown -R www-data:www-data /var/www/html

echo "🚀 Configuring Nginx reverse proxy for MinIO Console..."
NGINX_CONF="/etc/nginx/sites-available/minio.conf"

# Create initial Nginx configuration without SSL
cat <<EOF > $NGINX_CONF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root /var/www/html;

    # Dedicated location for ACME challenge
    location ^~ /.well-known/acme-challenge/ {
        default_type "text/plain";
        root /var/www/html;
    }

    # Proxy all other traffic to MinIO
    location / {
        proxy_pass http://127.0.0.1:9001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        send_timeout 300;
    }
}
EOF

# Enable the site and remove default
rm -f /etc/nginx/sites-enabled/default
ln -sf $NGINX_CONF /etc/nginx/sites-enabled/minio.conf

# Test and reload Nginx
nginx -t && systemctl restart nginx

echo "⏳ Waiting for DNS propagation (30 seconds)..."
sleep 30

# Verify DNS resolution
echo "🔍 Checking DNS resolution..."
host $DOMAIN || echo "Warning: DNS resolution failed"

# Check DuckDNS update status
echo "🔍 Checking DuckDNS update status..."
cat ~/duckdns/duck.log

# Test HTTP accessibility
echo "🔍 Testing HTTP accessibility..."
curl -v http://$DOMAIN >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ HTTP is accessible"
else
    echo "⚠️ HTTP is not accessible"
fi

echo "🚀 Obtaining SSL certificate with Certbot..."
# Try to obtain certificate
if certbot --nginx \
    --redirect \
    --agree-tos \
    --non-interactive \
    -d $DOMAIN \
    -m $EMAIL \
    --preferred-challenges http; then
    
    echo "✅ SSL setup complete."
    echo "➡️  Access MinIO at: https://$DOMAIN"
else
    echo "⚠️ Certbot failed. Running diagnostics..."
    
    # Check if ports are open
    echo "1. Checking ports..."
    nc -zv $DOMAIN 80
    nc -zv $DOMAIN 443
    
    # Check DNS resolution
    echo "2. Checking DNS..."
    dig +short $DOMAIN
    
    # Check Nginx status
    echo "3. Checking Nginx status..."
    systemctl status nginx --no-pager
    
    # Check Nginx logs
    echo "4. Last 10 lines of Nginx error log..."
    tail -n 10 /var/log/nginx/error.log
    
    echo "
⚠️ SSL certificate could not be obtained. Please:
1. Verify that $DOMAIN points to $(curl -s4 ifconfig.me)
2. Check that ports 80 and 443 are open:
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
3. Try running manually:
   sudo certbot --nginx -d $DOMAIN
"
fi

# Final status check
echo "
📝 Final Status:
1. Nginx Configuration: $(nginx -t 2>&1 >/dev/null && echo "✅ OK" || echo "❌ Failed")
2. DNS Resolution: $(host $DOMAIN >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed")
3. HTTP Port (80): $(nc -z $DOMAIN 80 2>/dev/null && echo "✅ Open" || echo "❌ Closed")
4. HTTPS Port (443): $(nc -z $DOMAIN 443 2>/dev/null && echo "✅ Open" || echo "❌ Closed")
"
