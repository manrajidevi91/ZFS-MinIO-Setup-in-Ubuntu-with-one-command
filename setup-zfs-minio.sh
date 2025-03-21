#!/bin/bash
set -e

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
echo "➡️  Access Console: http://<your-server-ip>:9001"
echo "➡️  Access API: http://<your-server-ip>:9000"
echo "🗂️  ZFS Storage: Mounted at /mnt/minio"
echo "🔎 To see the loop file details, run: losetup -a"
