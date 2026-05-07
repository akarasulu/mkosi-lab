# Session Log

Date: 2026-05-06
Host UI: VS Code on Windows (`planck`)
Development target: Debian WSL 2 (`Debian`)
Project path: `/home/aok/Local/Projects/pe-uki-lab`

## Goal

Create a Linux-hosted development project that can be edited from the Windows VS Code UI through the WSL remote extension. Use it to experiment with Python, uv, mkosi, and bootable PE/UKI artifacts.

## Environment discovered

- WSL default distribution: `Debian`
- WSL default version: `2`
- Debian version: Debian GNU/Linux 13 (`trixie`)
- Initial tools present: `python3`, `git`, VS Code `code` shim from Windows
- Initial tools missing: `uv`, `mkosi`
- Preferred project root adjusted to: `/home/aok/Local/Projects`

## Host packages installed in Debian WSL

Installed with apt:

```bash
sudo apt-get update
sudo apt-get install -y \
  curl ca-certificates python3-venv mkosi systemd-boot-efi \
  qemu-utils dosfstools mtools sbsigntool binutils file
```

This pulled in the broader mkosi image-building stack, including QEMU, systemd boot tooling, package manager helpers, and PE/signing-related utilities.

## uv installation

Installed uv with Astral's official Linux installer:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.local/bin/env
```

Verified:

```text
uv 0.11.9 (x86_64-unknown-linux-gnu)
Python 3.13.5
mkosi 25.3
```

## Project creation

Created a packaged uv project:

```bash
cd /home/aok/Local/Projects
uv init --package pe-uki-lab
cd pe-uki-lab
uv add --dev ruff pytest
```

Smoke checks:

```bash
uv run pe-uki-lab
uv run ruff check .
```

Results:

```text
Hello from pe-uki-lab!
All checks passed!
```

## mkosi baseline

Added `mkosi.conf` with Debian trixie, `Format=uki`, `linux-image-amd64`, Python, systemd, udev, dbus, kmod, and `systemd-boot-efi`.

Added `mkosi.extra/` overlay containing:

- `/usr/local/bin/pe-uki-lab`: Python boot payload
- `/etc/systemd/system/pe-uki-lab.service`: one-shot service
- `/etc/systemd/system/default.target.wants/pe-uki-lab.service`: enablement symlink

## Build notes

First build command:

```bash
sudo mkosi -f build
```

The first attempt installed the image packages and copied the overlay, then failed while installing systemd-boot because `systemd-boot-efi` was installed on the WSL host but not inside the image. Lesson: host packages and image packages are separate worlds.

Fix: add `systemd-boot-efi` to the mkosi image package list.

Second build succeeded and produced:

```text
mkosi.output/pe-uki-lab.efi
mkosi.output/pe-uki-lab.initrd
mkosi.output/pe-uki-lab.vmlinuz
```

Artifact sanity check:

```bash
file mkosi.output/pe-uki-lab.efi
objdump -h mkosi.output/pe-uki-lab.efi
```

Result summary:

```text
PE32+ executable for EFI (application), x86-64
sections include .sbat, .sdmagic, .osrel, .cmdline, .uname, .linux, .initrd
```

## VS Code remote entry points

From Windows PowerShell:

```powershell
code --remote wsl+Debian /home/aok/Local/Projects/pe-uki-lab
```

From Debian WSL:

```bash
cd /home/aok/Local/Projects/pe-uki-lab
code .
```
