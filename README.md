# mkosi Lab

A small uv-managed Python project for experimenting with mkosi-built Unified Kernel Images.

## Daily development

```bash
cd /home/aok/Local/Projects/pe-uki-lab
uv run pe-uki-lab
uv run ruff check .
uv run pytest
```

## Build the first UKI experiment

```bash
cd /home/aok/Local/Projects/pe-uki-lab
make build
```

The mkosi config builds a Debian trixie `Format=uki` image and overlays `mkosi.extra/` into the image. The included systemd service runs `/usr/local/bin/pe-uki-lab` during boot and writes to the console/journal.

Generated artifacts go under `mkosi.output/`; cache data goes under `mkosi.cache/`. The `make build` target also creates a tiny FAT Lab UKI ESP, copies the UKI to `EFI/BOOT/BOOTX64.EFI`, packages that disk as a local libvirt Vagrant box, and registers it as `nested/uki-boot`.

## Boot-test the UKI with Vagrant (UEFI/libvirt)

Prerequisites on the host:

```bash
sudo apt-get install -y qemu-system-x86 ovmf mtools dosfstools
vagrant plugin install vagrant-libvirt
```

Build and register the UKI boot box, then start the VM:

```bash
cd /home/aok/Local/Projects/pe-uki-lab
make build
make up
```

The `Vagrantfile` uses `nested/uki-boot` as the base box. That box contains a single qcow2 disk whose filesystem is the FAT Lab UKI ESP:

```text
vda:/EFI/BOOT/BOOTX64.EFI
```

The VM no longer depends on an external Debian base box or a second attached ESP disk.

Useful shortcuts:

```bash
make status
make ssh
make console
make down
make destroy
```

To stop/remove the VM:

```bash
make destroy
```

## Open from Windows VS Code

From PowerShell:

```powershell
code --remote wsl+Debian /home/aok/Local/Projects/pe-uki-lab
```

Or from Debian WSL:

```bash
cd /home/aok/Local/Projects/pe-uki-lab
code .
```

## Project notes

- `docs/session-log.md` records the setup session and build lessons.
- `docs/WSL-vagrant-quirks.md` documents the WSL/Vagrant/libvirt UEFI and networking failure chain.
- `docs/project-history.md` tracks the project baseline over time.
- `docs/recreate-project.md` explains how to recreate this project manually.
- `docs/ansible-baseline-role.md` explains the reusable Ansible role for stamping out similar projects.

## Create another project from the baseline role

```bash
cd /home/aok/Local/Projects/pe-uki-lab
ansible-playbook ansible/create-uv-mkosi-project.yml \
  -e project_name=another-uki-lab
```
