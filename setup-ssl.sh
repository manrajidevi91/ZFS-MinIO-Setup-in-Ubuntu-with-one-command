#!/bin/bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Verify domain and email
DOMAIN="zfs-minio.duckdns.org"
EMAIL="manrajidevi91@gmail.com"

echo "🔒 Setting up SSL for $DOMAIN..."
echo "📧 Using email: $EMAIL"
echo "⚠️ Please verify these details are correct (y/n)?"
read -r confirm

if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "❌ Setup cancelled"
    exit 1
fi

echo "🔒 Setting up SSL for zfs-minio.duckdns.org..."

# Stop Nginx temporarily
systemctl stop nginx

# Create webroot directory for ACME challenge
mkdir -p /var/www/html/.well-known/acme-challenge
chown -R www-data:www-data /var/www/html

# Create initial Nginx configuration for HTTP
cat <<'EOF' > /etc/nginx/sites-available/minio.conf
server {
    listen 80;
    listen [::]:80;
    server_name zfs-minio.duckdns.org;
    
    # Root directory for ACME challenge
    root /var/www/html;
    
    # Allow ACME challenge
    location ^~ /.well-known/acme-challenge/ {
        allow all;
        default_type "text/plain";
    }

    location / {
        proxy_pass http://127.0.0.1:9001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        send_timeout 300;
    }
}
EOF

# Enable the site
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/minio.conf /etc/nginx/sites-enabled/

# Start Nginx
systemctl start nginx

echo "⏳ Testing Nginx configuration..."
nginx -t

echo "🔍 Checking HTTP accessibility..."
curl -I http://zfs-minio.duckdns.org || echo "⚠️ HTTP check failed"

echo "🔒 Obtaining SSL certificate..."
certbot --nginx \
    --non-interactive \
    --agree-tos \
    --email manrajidevi91@gmail.com \
    --domains zfs-minio.duckdns.org \
    --redirect \
    --keep-until-expiring \
    --must-staple \
    --preferred-challenges http \
    --verbose

# Verify SSL configuration
if [ $? -eq 0 ]; then
    echo "✅ SSL certificate installed successfully!"
    
    # Test SSL configuration
    echo "🔍 Testing SSL configuration..."
    curl -I https://zfs-minio.duckdns.org || echo "⚠️ HTTPS check failed"
    
    echo """
    ✅ SSL Setup Complete!
    
    Your MinIO server is now accessible at:
    🔒 https://zfs-minio.duckdns.org
    
    SSL certificate will auto-renew via Certbot's renewal service.
    """
else
    echo """
    ⚠️ SSL setup failed. Manual troubleshooting required:
    
    1. Check DNS resolution:
    dig zfs-minio.duckdns.org
    
    2. Verify ports are open:
    sudo netstat -tulpn | grep '80\|443'
    
    3. Check Certbot logs:
    sudo tail -f /var/log/letsencrypt/letsencrypt.log
    
    4. Try manual certificate issuance:
    sudo certbot --nginx -d zfs-minio.duckdns.org
    """
fi

# Add strong SSL parameters
cat <<'EOF' > /etc/nginx/conf.d/ssl-params.conf
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_dhparam /etc/nginx/dhparam.pem;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
ssl_ecdh_curve secp384r1;
ssl_session_timeout 10m;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
add_header Strict-Transport-Security "max-age=63072000" always;
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
EOF

# Generate strong DH parameters
echo "⏳ Generating DH parameters (this may take a few minutes)..."
openssl dhparam -out /etc/nginx/dhparam.pem 2048

# Final Nginx restart
systemctl restart nginx

echo """
📝 Final Status:
1. HTTP-to-HTTPS redirect: ✅
2. SSL Configuration: ✅
3. Security Headers: ✅
4. Strong SSL Parameters: ✅

To verify the SSL setup:
1. Visit https://zfs-minio.duckdns.org
2. Check SSL rating: https://www.ssllabs.com/ssltest/analyze.html?d=zfs-minio.duckdns.org
"""

# Set up auto-renewal cron job
echo "0 */12 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" > /etc/cron.d/certbot-renew

echo "✅ Setup complete! Your MinIO server is now secured with SSL!"
