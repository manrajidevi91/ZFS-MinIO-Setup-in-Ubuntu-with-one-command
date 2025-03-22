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
