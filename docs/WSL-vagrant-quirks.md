# WSL, Vagrant, libvirt, and UEFI Quirks

Date: 2026-05-07
Context: Debian WSL 2 on Windows, Vagrant, vagrant-libvirt, qemu/libvirt, OVMF, and a mkosi-built UKI experiment.

This note records the failure chain behind the first working Vagrant/libvirt boot setup. The short version: the VM booted correctly, but networking failed because several layers made different assumptions about UEFI boot, disk attachment, and the guest's first Ethernet interface.

## Summary

The working setup depends on three explicit choices in the `Vagrantfile`:

- Use q35 plus OVMF firmware for UEFI boot.
- In WSL, use qemu mode and a writable OVMF vars image.
- Package the Lab UKI ESP as the local `nested/uki-boot` libvirt Vagrant box, so the UKI disk is the primary boot disk.
- Pin the libvirt management NIC to PCI bus `0x05`, slot `0x00`, so the PCI topology stays stable while debugging.

The default Vagrant synced folder is also disabled because rsyncing the whole project copies `mkosi.output/`, `.venv/`, and other generated artifacts into the guest.

## ESP Naming

The current `box-it-up` branch packages the Lab UKI ESP as the only disk in the local `nested/uki-boot` Vagrant box:

```text
vda:/EFI/BOOT/BOOTX64.EFI
```

The generated box contains:

```text
metadata.json
Vagrantfile
box.img
```

`box.img` is a qcow2 container whose filesystem is the FAT Lab UKI ESP. Vagrant/libvirt copies that box disk into the libvirt storage pool as `/var/lib/libvirt/images/pe-uki-lab_default.img`, and the guest sees it as `vda`.

Older experiments had two different EFI System Partitions:

- **Base box ESP**: `vda1`
  This is part of the Vagrant base box disk, `/var/lib/libvirt/images/pe-uki-lab_default.img`. It belongs to the Debian box image and is not the artifact under test.

- **Lab UKI ESP**: `sda1`
  This is the attached raw ESP disk image, `/var/lib/libvirt/images/pe-uki-lab-esp.img`. It is the artifact under test and should contain the mkosi-generated UKI at `EFI/BOOT/BOOTX64.EFI`.

That two-disk model worked, but it left a confusing unused base image in the VM. The boxed model removes that ambiguity: there is no external Debian base box in the running domain.

For a direct UEFI fallback boot test, the Lab UKI ESP contains the UKI as a real FAT file:

```text
vda:/EFI/BOOT/BOOTX64.EFI
```

FAT does not support Unix symlinks, and UEFI fallback boot expects a real file at `\EFI\BOOT\BOOTX64.EFI`. To avoid storing the same UKI twice, store it only at that fallback path.

The current boxed model has a single boot disk. In libvirt XML, the useful evidence is:

```xml
<source file='/var/lib/libvirt/images/pe-uki-lab_default.img'/>
<target dev='vda' bus='virtio'/>
<boot order='1'/>
```

Runtime proof still matters. The current UKI boot can be verified by checking that the guest reports the mkosi kernel command line, Debian trixie userspace, and the Lab UKI ESP as `vda`:

```bash
vagrant ssh -c "cat /proc/cmdline; cat /etc/os-release; lsblk -f"
```

Expected evidence in the boxed model:

- `/proc/cmdline` contains `console=ttyS0`.
- `/etc/os-release` reports Debian 13/trixie from the mkosi UKI userspace.
- `lsblk -f` shows only `vda` as `vfat` with label `LABUKIESP`.

## WSL Host Constraints

Debian inside WSL 2 is not the same operating environment as a normal bare-metal Linux host. In this project, the important differences were:

- KVM availability may be missing or unreliable depending on the WSL setup.
- OVMF firmware paths vary by distro/package version.
- qemu/libvirt access to files can be surprising when images live in project paths rather than libvirt storage paths.
- Vagrant's usual provider defaults are tuned for ordinary boxes, not for booting custom UEFI/UKI artifacts.

The `Vagrantfile` therefore discovers OVMF loader and variable templates from several candidate paths, copies writable NVRAM vars into `/tmp`, and uses q35/OVMF explicitly.

## Vagrant-libvirt UEFI Limitations

The vagrant-libvirt provider can create and start UEFI guests, but it does not remove the need to be precise about the domain XML. For this lab, these details mattered:

- `machine_type = "q35"` is required for the intended PCI/UEFI topology.
- `loader` must point at an OVMF code image.
- `nvram` must point at a writable OVMF vars image.
- The generated ESP image must be present as the primary box disk the guest firmware can see.
- Boot order must prefer the disk path that contains the expected UEFI boot entry.

Without those pieces, failures can look like generic firmware boot hangs or a VM that starts but never reaches the expected OS path.

## Management NIC Mismatch

The most deceptive failure was networking.

Observed symptoms:

- `vagrant up --provider=libvirt` created and started the VM.
- The guest reached the Debian login prompt.
- Vagrant hung at:

```text
Waiting for domain to get an IP address...
```

The host-side network looked healthy:

```bash
virsh -c qemu:///system net-list --all
virsh -c qemu:///system net-info vagrant-libvirt
virsh -c qemu:///system domiflist pe-uki-lab_default
sudo pgrep -af dnsmasq
```

The important negative evidence was that no DHCP packets arrived:

```bash
timeout 12 sudo tcpdump -ni virbr1 -vvv port 67 or port 68
```

Result:

```text
0 packets captured
```

That ruled out a host DHCP lease parsing problem. The guest was not asking for DHCP at all.

Inspecting the base box image showed why:

```bash
env LIBGUESTFS_BACKEND=direct LIBGUESTFS_CACHEDIR=/tmp \
  virt-cat \
  -a /var/lib/libvirt/images/ncrmro-VAGRANTSLASH-debian-bookworm64-uefi_vagrant_box_image_1.0.0_box.img \
  -m /dev/sda2 \
  /etc/network/interfaces
```

The box configures:

```text
allow-hotplug enp5s0
iface enp5s0 inet dhcp
```

But libvirt initially placed the management NIC on a different PCI bus, so Linux named it differently. The interface configured for DHCP did not exist, so the guest never emitted DHCP traffic.

The fix is to pin the management NIC where the box expects it:

```ruby
libvirt.management_network_pci_bus = "0x05"
libvirt.management_network_pci_slot = "0x00"
```

After that, the domain XML contains:

```xml
<address type='pci' domain='0x0000' bus='0x05' slot='0x00' function='0x0'/>
```

And the guest comes up with DHCP on `enp5s0`.

Verification:

```bash
virsh -c qemu:///system net-dhcp-leases vagrant-libvirt
vagrant ssh -c "ip -br addr show enp5s0 && systemctl is-active networking ssh"
```

Expected result:

```text
enp5s0 UP 192.168.121.x/24 ...
active
active
```

## Rsync Artifact Bloat

Vagrant's default synced folder copies the project root to `/vagrant` with rsync. That is a poor fit for this lab because the project root contains generated image artifacts:

- `mkosi.output/`
- `mkosi.cache/`
- `.venv/`
- libvirt/qemu image files such as `*.img`, `*.raw`, and `*.qcow2`

In one run, `/vagrant` inside the guest grew to hundreds of MiB because `mkosi.output/` was copied into the VM. This slows startup and inflates the guest qcow2 snapshot.

The current fix is to disable the root synced folder:

```ruby
config.vm.synced_folder ".", "/vagrant", disabled: true
```

If a VM was already created before disabling sync, Vagrant may have cached the old synced-folder state under:

```text
.vagrant/machines/default/libvirt/synced_folders
```

Reloading refreshes that cache:

```bash
vagrant reload --no-provision
cat .vagrant/machines/default/libvirt/synced_folders
```

Expected result:

```json
{"rsync":{}}
```

To clean already-copied files from an existing guest:

```bash
vagrant ssh -c "rm -rf \
  /vagrant/.git \
  /vagrant/.vagrant \
  /vagrant/.venv \
  /vagrant/.ruff_cache \
  /vagrant/mkosi.cache \
  /vagrant/mkosi.output \
  /vagrant/mkosi.workspace \
  /vagrant/*.img \
  /vagrant/*.raw \
  /vagrant/*.qcow2"
```

Deleting files inside the guest does not automatically shrink the host qcow2 file. To get a compact fresh VM after accidental rsync bloat:

```bash
vagrant destroy -f
vagrant up --provider=libvirt
```

## UKI Userspace Login and Networking

The mkosi `Format=uki` output used here is a self-contained Debian userspace in the UKI initrd. Package selection matters:

- `login` is required for password login on the serial console. Without it, `agetty` can print `localhost login:` but returns to the prompt after a username because there is no login program to exec.
- `iproute2` is required for the `ip` command.
- `iputils-ping`, `net-tools`, `bind9-dnsutils`, `traceroute`, `tcpdump`, `ethtool`, `curl`, and `ca-certificates` provide the usual network debugging tools.
- `systemd-networkd` needs an image-side `.network` file to request DHCP when booted directly through libvirt/OVMF.
- `openssh-server`, `sudo`, a `vagrant` user, and Vagrant's insecure public key make the UKI userspace compatible with Vagrant's SSH communicator.

Current DHCP config:

```ini
# mkosi.extra/etc/systemd/network/20-dhcp.network
[Match]
Name=en* eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes
```

The `Vagrantfile` NIC pin means the management NIC appears as `enp5s0`, so this broad match includes it.

The `vagrant` user is created by:

```text
mkosi.extra/usr/lib/sysusers.d/pe-uki-lab.conf
```

Its authorized key is the standard Vagrant insecure public key:

```text
mkosi.extra/home/vagrant/.ssh/authorized_keys
```

The Vagrantfile sets:

```ruby
config.ssh.username = "vagrant"
config.ssh.insert_key = false
```

Copying `mkosi.extra/home/vagrant/.ssh/authorized_keys` into the image is not sufficient by itself. Files copied from `mkosi.extra` land in the image as `root:root`, and Debian OpenSSH defaults to `StrictModes yes`. That means this live state breaks key authentication for the `vagrant` user:

```text
/home/vagrant                      root root 755
/home/vagrant/.ssh                 root root 700
/home/vagrant/.ssh/authorized_keys root root 600
```

The image therefore includes a boot-time setup unit:

```text
mkosi.extra/etc/systemd/system/pe-uki-lab-vagrant-setup.service
mkosi.extra/usr/local/libexec/pe-uki-lab-vagrant-setup
```

It runs after `systemd-sysusers.service` and before `ssh.service`, sets a usable `vagrant` password hash, and repairs ownership and permissions:

```text
/home/vagrant                      vagrant vagrant 755
/home/vagrant/.ssh                 vagrant vagrant 700
/home/vagrant/.ssh/authorized_keys vagrant vagrant 600
```

Verification from the host:

```bash
vagrant ssh -c "passwd -S vagrant; stat -c '%U %G %a %n' /home/vagrant /home/vagrant/.ssh /home/vagrant/.ssh/authorized_keys; systemctl is-active pe-uki-lab-vagrant-setup.service ssh.service"
```

Debian's OpenSSH package may also enable `ssh.socket` through presets. That can produce this harmless but noisy boot warning:

```text
systemd[1]: sockets.target: Job ssh.socket/start deleted to break ordering cycle starting with sockets.target/start
[ SKIP ] Ordering cycle found, skipping ssh.socket
```

The cycle happens because this lab deliberately needs the Vagrant account repair to happen before SSH accepts logins. Socket activation is the wrong shape for that: `ssh.socket` belongs to `sockets.target`, while the repair service is enabled in `multi-user.target` and orders itself before the SSH daemon.

The fix is to mask `ssh.socket` in the image and enable `ssh.service` directly:

```text
mkosi.extra/etc/systemd/system/ssh.socket -> /dev/null
mkosi.extra/etc/systemd/system/multi-user.target.wants/ssh.service -> ../../../../usr/lib/systemd/system/ssh.service
```

The Vagrant account repair unit should order before the service, not the socket:

```ini
After=systemd-sysusers.service
Before=ssh.service sshd.service
```

This makes startup deterministic: create `vagrant`, repair `/home/vagrant` ownership and password state, then start `ssh.service`.

`insert_key = false` is intentional. The UKI initrd is rebuilt frequently, so rotating the insecure key into the running guest would only last until the next rebuild/reboot.

This SSH compatibility does not by itself choose the boot disk. The boot-source distinction still matters, but the boxed model makes it simpler:

- `vda` is the only disk in the running domain.
- `vda` is the Lab UKI ESP packaged into the `nested/uki-boot` box.

For a true UKI test, the domain should show `vda` with boot order 1 and `lsblk -f` should show `vda` as `vfat` with label `LABUKIESP`.

## Debugging Checklist

Use this order when Vagrant hangs during startup:

1. Confirm whether the VM booted:

```bash
virsh -c qemu:///system list --all
virsh -c qemu:///system screenshot pe-uki-lab_default /tmp/pe-uki-lab-screen.ppm
```

2. Confirm libvirt attached a NIC:

```bash
virsh -c qemu:///system domiflist pe-uki-lab_default
virsh -c qemu:///system dumpxml pe-uki-lab_default
```

3. Confirm the Vagrant network and dnsmasq are alive:

```bash
virsh -c qemu:///system net-info vagrant-libvirt
virsh -c qemu:///system net-dhcp-leases vagrant-libvirt
sudo pgrep -af dnsmasq
```

4. Capture DHCP on the bridge:

```bash
timeout 12 sudo tcpdump -ni virbr1 -vvv port 67 or port 68
```

5. If DHCP is absent, inspect guest network config and compare it with the libvirt PCI address:

```bash
virsh -c qemu:///system dumpxml pe-uki-lab_default
```

6. After changing Vagrant synced-folder or network definitions, reload or recreate the VM so cached provider state matches the `Vagrantfile`:

```bash
vagrant reload --no-provision
```

## Lesson

This was not one bug. It was a boundary problem across WSL, Vagrant, libvirt XML, qemu/OVMF, and Debian guest network naming. The durable fix was to stop relying on provider defaults and make the firmware, disk, NIC topology, and synced-folder behavior explicit.
