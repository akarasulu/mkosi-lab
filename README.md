# pe-uki-lab

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
sudo mkosi -f build
```

The mkosi config builds a Debian trixie `Format=uki` image and overlays `mkosi.extra/` into the image. The included systemd service runs `/usr/local/bin/pe-uki-lab` during boot and writes to the console/journal.

Generated artifacts go under `mkosi.output/`; cache data goes under `mkosi.cache/`.

## Boot-test the UKI with Vagrant (UEFI/libvirt)

Prerequisites on the host:

```bash
sudo apt-get install -y qemu-system-x86 ovmf mtools dosfstools
vagrant plugin install vagrant-libvirt
```

Build the UKI, then start the VM:

```bash
cd /home/aok/Local/Projects/pe-uki-lab
sudo mkosi -f build
vagrant up --provider=libvirt
```

The `Vagrantfile` creates a tiny FAT EFI System Partition image under `.vagrant/uki/`, copies `mkosi.output/pe-uki-lab.efi` to `EFI/BOOT/BOOTX64.EFI`, and boots a UEFI guest from it.

To stop/remove the VM:

```bash
vagrant destroy -f
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
- `docs/project-history.md` tracks the project baseline over time.
- `docs/recreate-project.md` explains how to recreate this project manually.
- `docs/ansible-baseline-role.md` explains the reusable Ansible role for stamping out similar projects.

## Create another project from the baseline role

```bash
cd /home/aok/Local/Projects/pe-uki-lab
ansible-playbook ansible/create-uv-mkosi-project.yml \
  -e project_name=another-uki-lab
```
