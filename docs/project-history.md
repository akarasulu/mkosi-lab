# Project History

## 2026-05-06: Initial WSL uv/mkosi lab

This project began as a small lab for learning several tools together:

- VS Code Remote - WSL for editing Linux files from the Windows UI
- uv for Python project and environment management
- mkosi for building bootable Unified Kernel Images
- Debian WSL as the development and build environment

The project was intentionally placed under `/home/aok/Local/Projects` instead of `/mnt/c/...` so the repository lives on the Linux filesystem. That avoids cross-filesystem friction and gives Linux tools normal permissions, symlinks, path semantics, and better performance.

The first working baseline is a packaged uv project with a mkosi `Format=uki` configuration. The mkosi overlay adds a tiny Python boot payload and a systemd service that runs during boot.

The first mkosi build exposed an important packaging boundary: installing `systemd-boot-efi` on the WSL host is not enough. If the generated image needs those EFI bootloader files, the package must also be listed in `mkosi.conf` under `[Content] Packages=`.

The first successful build generated an unsigned x86-64 EFI application at `mkosi.output/pe-uki-lab.efi`.

## Current baseline

The current baseline includes:

- `pyproject.toml`: packaged uv Python app
- `uv.lock`: locked Python dependency state
- `mkosi.conf`: Debian trixie UKI image definition
- `mkosi.extra/`: files copied into the generated image
- `docs/`: setup/history/recreation notes
- `ansible/`: reusable baseline role for creating similar projects

## Direction

The next natural experiments are:

- boot/test the UKI in QEMU
- move the boot payload into the packaged Python module instead of a standalone overlay script
- add Secure Boot signing experiments
- split reusable project scaffolding into an Ansible collection or separate repository if it becomes useful across many projects
