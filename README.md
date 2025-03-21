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
curl -sSL https://raw.githubusercontent.com/your-username/server-setup-scripts/main/setup-zfs-minio.sh | sudo bash
```

> Replace `your-username` and repo path with your GitHub account details.

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
