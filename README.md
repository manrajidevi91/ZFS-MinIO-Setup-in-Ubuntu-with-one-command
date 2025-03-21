# 🚀 ZFS + MinIO Setup Script for Ubuntu

This repository contains a one-click setup script to install and configure **ZFS** with **MinIO** on **Ubuntu**.  
It automates everything: pool creation, dataset mounting, MinIO installation, and systemd setup.

---

## 📦 Features

- Installs `zfsutils-linux` (ZFS)
- Creates ZFS pool (`zpool1`) on `/dev/sdb`
- Creates and mounts dataset at `/mnt/minio`
- Installs and configures MinIO server
- Automatically starts MinIO as a service on boot
- Sets up MinIO Console on port `9001`, API on port `9000`

---

## 🖥️ Requirements

- Ubuntu 20.04 or later
- Root or sudo privileges
- One unused disk (e.g., `/dev/sdb`) for ZFS

---

## ⚙️ Usage

### 📥 Run in One Command

```bash
curl -sSL https://raw.githubusercontent.com/manrajidevi91/ZFS-MinIO-Setup-in-Ubuntu-with-one-command/main/setup-zfs-minio.sh | sudo bash
```

---

## 📍 Where Can You Install This?

This script is designed to work in the following environments:

### 1. **Local Ubuntu Machine**
```bash
# Recommended for personal use, testing, or small deployments
curl -sSL https://raw.githubusercontent.com/manrajidevi91/ZFS-MinIO-Setup-in-Ubuntu-with-one-command/main/setup-zfs-minio.sh | sudo bash
```

### 2. **Cloud VM (AWS EC2, DigitalOcean, Linode, etc.)**
```bash
# Make sure the VM has a secondary attached disk (e.g., /dev/sdb)
# SSH into your cloud VM and run:
curl -sSL https://raw.githubusercontent.com/manrajidevi91/ZFS-MinIO-Setup-in-Ubuntu-with-one-command/main/setup-zfs-minio.sh | sudo bash
```

### 3. **Bare Metal Server**
```bash
# Ideal for production setups with physical disks
curl -sSL https://raw.githubusercontent.com/manrajidevi91/ZFS-MinIO-Setup-in-Ubuntu-with-one-command/main/setup-zfs-minio.sh | sudo bash
```

### 4. **Ubuntu Server in Proxmox or VirtualBox**
```bash
# If using a virtual disk as /dev/sdb
curl -sSL https://raw.githubusercontent.com/manrajidevi91/ZFS-MinIO-Setup-in-Ubuntu-with-one-command/main/setup-zfs-minio.sh | sudo bash
```

### 5. **Docker Container with Privileged Access**
```bash
# If you're running Ubuntu inside a Docker container with access to /dev/sdb and ZFS modules,
# you can still run this script. Make sure your container has privileged access and the necessary mounts.

docker run --rm -it --privileged   -v /dev:/dev   -v /lib/modules:/lib/modules   ubuntu bash -c "apt update && apt install -y curl &&   curl -sSL https://raw.githubusercontent.com/manrajidevi91/ZFS-MinIO-Setup-in-Ubuntu-with-one-command/main/setup-zfs-minio.sh | bash"
```

> ⚠️ ZFS inside Docker requires kernel module access and privileged mode.

---

## 🗂️ File Structure

| File                | Description                      |
|---------------------|----------------------------------|
| `setup-zfs-minio.sh` | Main installer and configurator |

---

## 🔐 Default Credentials

- Username: `admin`
- Password: `adminpassword`

---

## 📡 Access

- MinIO Console: `http://<your-ip>:9001`
- MinIO API: `http://<your-ip>:9000`
- Data Path: `/mnt/minio/data`

---

## 🛡️ Notes

- You can modify the ZFS pool name or device by editing the script.
- To support custom environments or mounts, adapt the script accordingly.

---

## 📃 License

MIT License
