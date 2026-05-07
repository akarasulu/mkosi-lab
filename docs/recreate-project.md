# Recreate This Project

This document describes how to recreate the current project baseline on a fresh Debian WSL instance.

## 1. Open Debian WSL

From Windows PowerShell:

```powershell
wsl -d Debian
```

Keep project files under the Linux filesystem:

```bash
mkdir -p /home/aok/Local/Projects
cd /home/aok/Local/Projects
```

Avoid creating this kind of project under `/mnt/c/...` unless you specifically need the files on the Windows filesystem.

## 2. Install host tools

```bash
sudo apt-get update
sudo apt-get install -y \
  curl ca-certificates git python3 python3-venv \
  mkosi systemd-boot-efi qemu-utils dosfstools mtools \
  sbsigntool binutils file ansible
```

## 3. Install uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.local/bin/env
```

Verify:

```bash
uv --version
python3 --version
mkosi --version
```

## 4. Create the uv project

```bash
cd /home/aok/Local/Projects
uv init --package pe-uki-lab
cd pe-uki-lab
uv add --dev ruff pytest
```

## 5. Add mkosi configuration

Create `mkosi.conf`:

```ini
[Distribution]
Distribution=debian
Release=trixie
Architecture=x86-64

[Output]
Format=uki
Output=pe-uki-lab
OutputDirectory=mkosi.output

[Build]
CacheDirectory=mkosi.cache

[Content]
Packages=systemd
         udev
         linux-image-amd64
         python3
         kmod
         dbus
         systemd-boot-efi
KernelCommandLine=console=ttyS0 quiet
```

## 6. Add the boot payload overlay

```bash
mkdir -p mkosi.extra/usr/local/bin
mkdir -p mkosi.extra/etc/systemd/system/default.target.wants
```

Create `mkosi.extra/usr/local/bin/pe-uki-lab`:

```python
#!/usr/bin/env python3
from datetime import datetime, timezone

print("pe-uki-lab boot payload reached")
print(f"utc={datetime.now(timezone.utc).isoformat()}")
```

Make it executable:

```bash
chmod +x mkosi.extra/usr/local/bin/pe-uki-lab
```

Create `mkosi.extra/etc/systemd/system/pe-uki-lab.service`:

```ini
[Unit]
Description=PE UKI lab Python payload
After=basic.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pe-uki-lab
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes

[Install]
WantedBy=default.target
```

Enable it in the image:

```bash
ln -s ../pe-uki-lab.service \
  mkosi.extra/etc/systemd/system/default.target.wants/pe-uki-lab.service
```

## 7. Build

```bash
sudo mkosi -f build
```

Expected outputs:

```text
mkosi.output/pe-uki-lab.efi
mkosi.output/pe-uki-lab.initrd
mkosi.output/pe-uki-lab.vmlinuz
```

Check the EFI artifact:

```bash
file mkosi.output/pe-uki-lab.efi
objdump -h mkosi.output/pe-uki-lab.efi | sed -n '1,80p'
```

## 8. Open in VS Code

From Windows PowerShell:

```powershell
code --remote wsl+Debian /home/aok/Local/Projects/pe-uki-lab
```
