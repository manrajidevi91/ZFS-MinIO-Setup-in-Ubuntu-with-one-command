#!/bin/bash

set -e

echo "🚀 Installing ZFS..."
apt update
apt install -y zfsutils-linux

echo "🔍 Searching for a truly unused and safe disk (excluding system disks and optical drives)..."
AVAILABLE_DISK=$(lsblk -dpno NAME,TYPE,MOUNTPOINT | awk '$2=="disk" && $3=="" {print $1}' | grep -Ev '^/dev/sda$|^/dev/sr0$' | head -n 1)

if [ -z "$AVAILABLE_DISK" ]; then
  echo "❌ No safe available disk found to create a ZFS pool."
  exit 1
else
  echo "✅ Using available disk: $AVAILABLE_DISK"
fi

echo "📦 Creating ZFS Pool (zpool1) on $AVAILABLE_DISK..."
zpool create -f zpool1 "$AVAILABLE_DISK"

echo "📁 Creating ZFS Dataset for MinIO..."
zfs create zpool1/minio

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
echo "➡️  Access Console: http://<your-server-ip>:9001"
echo "➡️  Access API: http://<your-server-ip>:9000"
echo "🗂️  ZFS Storage: Mounted at /mnt/minio"
