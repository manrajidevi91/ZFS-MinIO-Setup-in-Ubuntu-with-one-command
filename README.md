# 🚀 ZFS + MinIO Setup Scripts (Ubuntu, Windows, Docker)

This repository provides all-in-one setup scripts to install and configure **MinIO** for content delivery across platforms.

---

## 📦 Features

- ✅ Ubuntu Linux: ZFS + MinIO fully automated setup
- ✅ Windows: Portable MinIO server setup via `.bat` file
- ✅ Docker: Privileged container setup with MinIO support
- 📁 Automatic storage mounting and bucket creation
- 🔐 MinIO console and S3 API access

---

## 🖥️ Requirements

| Platform | Requirements |
|----------|--------------|
| **Ubuntu** | Ubuntu 20.04+ and one unused disk (e.g., `/dev/sdb`) |
| **Windows** | Windows 10/11 with PowerShell and admin access |
| **Docker** | Host system with Docker and privileged mode access |

---

## ⚙️ One-Liner Setup (Ubuntu)

```bash
curl -sSL https://raw.githubusercontent.com/manrajidevi91/ZFS-MinIO-Setup-in-Ubuntu-with-one-command/main/setup-zfs-minio.sh | sudo bash
```

---

## 📍 Where Can You Install This?

### ✅ 1. Local Ubuntu Machine
```bash
curl -sSL https://raw.githubusercontent.com/manrajidevi91/ZFS-MinIO-Setup-in-Ubuntu-with-one-command/main/setup-zfs-minio.sh | sudo bash
```

### ✅ 2. Cloud VM (AWS, DigitalOcean, etc.)
Ensure a secondary disk is available as `/dev/sdb`, then run:
```bash
curl -sSL https://raw.githubusercontent.com/manrajidevi91/ZFS-MinIO-Setup-in-Ubuntu-with-one-command/main/setup-zfs-minio.sh | sudo bash
```

### ✅ 3. Bare Metal Server
Same command as above.

### ✅ 4. Ubuntu VM (Proxmox, VirtualBox)
Attach a virtual disk and run:
```bash
curl -sSL https://raw.githubusercontent.com/manrajidevi91/ZFS-MinIO-Setup-in-Ubuntu-with-one-command/main/setup-zfs-minio.sh | sudo bash
```

### ✅ 5. Docker Container
```bash
docker run --rm -it --privileged   -v /dev:/dev   -v /lib/modules:/lib/modules   ubuntu bash -c "apt update && apt install -y curl &&   curl -sSL https://raw.githubusercontent.com/manrajidevi91/ZFS-MinIO-Setup-in-Ubuntu-with-one-command/main/setup-zfs-minio.sh | bash"
```

> ⚠️ Requires privileged access and `/dev/sdb` passthrough.

---

## 🪟 Windows Setup (MinIO Only)

Use the included `setup_minio.bat` for standalone MinIO setup on Windows.

### ▶️ How to Use

1. Clone the Repo:
```powershell
git clone https://github.com/manrajidevi91/ZFS-MinIO-Setup-in-Ubuntu-with-one-command.git
cd ZFS-MinIO-Setup-in-Ubuntu-with-one-command
```

2. Run the Script:
```powershell
cd E:\Work\Server\MinIO
.\setup_minio.bat
```
> Or right-click and run as Administrator

### 🧰 What it Does

- Creates MinIO storage directory
- Sets environment variables
- Downloads and runs MinIO server on port 9000
- Starts MinIO Console on port 9001
- Creates `video-bucket` and makes it public

---

## 🔐 Default Credentials

- Username: `admin`
- Password: `adminpassword`

---

## 📡 Access

| Component | URL |
|----------|-----|
| MinIO Console | http://127.0.0.1:9001 or http://<your-ip>:9001 |
| MinIO API     | http://127.0.0.1:9000 or http://<your-ip>:9000 |

---

## 🗂️ File Structure

| File                | Description                      |
|---------------------|----------------------------------|
| `setup-zfs-minio.sh` | Ubuntu (ZFS + MinIO) setup script |
| `setup_minio.bat`    | Windows MinIO setup script       |

---

🧩 Proxmox VM Disk Passthrough (Optional)
If you're running this setup in Proxmox, and you want to passthrough a disk from one VM (e.g., vm-101) to another (e.g., vm-100), you can use the following command:

bash
Copy
Edit
qm set 100 -virtio1 /dev/pve/vm-101-disk-0
🔍 Explanation:
qm set 100: Configure VM with ID 100

-virtio1: Attach the disk as a virtio drive on slot 1

/dev/pve/vm-101-disk-0: Path to the disk used by VM 101 (must be unused or detached)

📝 Make sure the disk is not currently attached or in use by another VM before assigning it.

## 🛡️ Notes

- You can modify disk path `/dev/sdb` or bucket name `video-bucket` in the scripts.
- ZFS requires root privileges and available disk for pool creation.
- Docker setup must be privileged to use ZFS (or use MinIO alone without ZFS).

---

## 📃 License

MIT License
