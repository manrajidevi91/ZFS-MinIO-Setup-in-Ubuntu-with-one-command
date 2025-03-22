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

# Create the update script with IPv6 support
cat << 'EOF' > "$DUCKDNS_SCRIPT"
#!/bin/bash
DUCKDNS_TOKEN="$1"
DUCKDNS_SUBDOMAIN="$2"

# Get IPv6 address
IPV6=$(ip -6 addr show scope global | grep -v deprecated | grep -oP '(?<=inet6 )[0-9a-f:]+' | head -n 1)

if [ -z "$IPV6" ]; then
    echo "❌ No IPv6 address found"
    exit 1
fi

# Update DuckDNS with IPv6
echo "Updating DuckDNS with IPv6: $IPV6"
curl -k -s "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ipv6=${IPV6}" -o ~/duckdns/duck.log

# Check update status
if grep -q "OK" ~/duckdns/duck.log; then
    echo "✅ DuckDNS IPv6 update successful"
else
    echo "❌ DuckDNS update failed"
    cat ~/duckdns/duck.log
fi
EOF

# Make the script executable
chmod 700 "$DUCKDNS_SCRIPT"

# Test DuckDNS script once manually
bash "$DUCKDNS_SCRIPT" "$DUCKDNS_TOKEN" "$DUCKDNS_SUBDOMAIN"

# Set up cron job
(crontab -l 2>/dev/null | grep -v "$DUCKDNS_SCRIPT"; echo "*/5 * * * * $DUCKDNS_SCRIPT '$DUCKDNS_TOKEN' '$DUCKDNS_SUBDOMAIN' >/dev/null 2>&1") | crontab -

echo "✅ DuckDNS update script created at $DUCKDNS_SCRIPT"
echo "✅ Cron job set to run every 5 minutes"

# Configure firewall to allow ports 80, 443, and 9001
echo "🔧 Configuring firewall rules..."
if command -v ufw >/dev/null; then
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 9001/tcp
    echo "✅ UFW rules added for ports 80, 443, and 9001"
else
    # If UFW is not installed, try using iptables directly
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -p tcp --dport 9001 -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 80 -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 9001 -j ACCEPT
    echo "✅ iptables rules added for ports 80, 443, and 9001"
fi

# Update Nginx configuration to listen on IPv6 and proxy port 9001
cat << EOF > /etc/nginx/sites-available/minio.conf
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    # Allow ACME challenge for Let's Encrypt
    location ^~ /.well-known/acme-challenge/ {
        allow all;
        root /var/www/html;
    }

    # Proxy to MinIO Console
    location / {
        proxy_pass http://[::1]:9001;
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

# Enable the site and restart Nginx
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/minio.conf /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

echo """
📝 Configuration Summary:
1. DuckDNS IPv6 update script: $DUCKDNS_SCRIPT
2. Domain: $DOMAIN
3. Local MinIO Console: http://[::1]:9001
4. Public access: http://$DOMAIN
5. Ports opened: 80, 443, 9001
6. Current IPv6: $(ip -6 addr show scope global | grep -v deprecated | grep -oP '(?<=inet6 )[0-9a-f:]+' | head -n 1)

To test IPv6 connectivity:
1. curl -6 http://$DOMAIN
2. Check DuckDNS logs: cat ~/duckdns/duck.log
3. View IPv6 address: ip -6 addr show scope global
"""

# Final verification
echo "🔍 Running final checks..."
echo "1. Testing IPv6 connectivity..."
curl -6 --connect-timeout 5 http://$DOMAIN || echo "⚠️ IPv6 connection failed"

echo "2. Checking DuckDNS record..."
host -t AAAA $DOMAIN || echo "⚠️ No AAAA record found"

echo "3. Verifying port 9001..."
nc -z -v localhost 9001 || echo "⚠️ Port 9001 not accessible locally"
