#!/bin/bash
set -e

# Set variables
DOMAIN="zfs-minio.duckdns.org"
EMAIL="manrajidevi91@gmail.com"

echo "🔒 Starting automatic SSL setup for $DOMAIN..."
echo "📧 Using email: $EMAIL"

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
    
    root /var/www/html;
    
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
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
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
curl -I http://zfs-minio.duckdns.org

echo "🔒 Obtaining SSL certificate..."
certbot --nginx \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    --domains "$DOMAIN" \
    --redirect \
    --keep-until-expiring \
    --preferred-challenges http

if [ $? -eq 0 ]; then
    echo "✅ SSL certificate installed successfully!"
    
    # Add strong SSL parameters
    cat <<'EOF' > /etc/nginx/conf.d/ssl-params.conf
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
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

    # Restart Nginx to apply SSL configuration
    systemctl restart nginx

    echo """
    ✅ SSL Setup Complete!
    
    Your MinIO server is now accessible at:
    🔒 https://zfs-minio.duckdns.org
    
    SSL certificate will auto-renew via Certbot's renewal service.
    """
else
    echo "⚠️ SSL setup failed. Check /var/log/letsencrypt/letsencrypt.log for details"
fi

# Set up auto-renewal cron job
echo "0 */12 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" > /etc/cron.d/certbot-renew

echo "✅ Setup complete!"
