# Operator USB/IP Process

Use this process when an operator is issuing a physical installer USB from
`provcont` and signing provenance with a local HSM such as a YubiKey. The goal is
to pass the USB device identity into `provcont`, not to expose only a generic
block device. USB/IP is the normal production and test path. Libvirt USB
passthrough stays in the lab as an explicit diagnostic or emergency fallback.

## Windows Workstation Setup

Prepare the Windows operator workstation:

```powershell
infra\scripts\install-windows-deps.ps1
```

The helper installs `usbipd-win` with `winget` when missing and starts the
`usbipd` service. The installer provides the `usbipd` service and opens the
Windows Firewall path needed for USB/IP. Keep the firewall narrowed to trusted
`provcont` addresses on the operator/lab network; no other host should be able
to reach the Windows USB/IP service.

Plug in the target installer USB and the HSM. In an elevated PowerShell prompt,
list devices and bind only the expected devices:

```powershell
usbipd list
usbipd bind --busid <target-usb-busid>
usbipd bind --busid <hsm-busid>
```

Binding makes the devices exportable. Do not run `usbipd attach --wsl` for the
issuance path. `provcont` should import the devices directly from Windows so the
media issuance record sees the real USB transport, VID:PID, model, serial, and
removable/hotplug metadata.

## Linux Workstation Setup

Prepare a Linux operator workstation with the infra bootstrap script:

```bash
infra/scripts/install-linux-deps.sh
```

The helper installs the Linux USB/IP tooling, tries to load the `usbip-core` and
`usbip-host` modules, and enables `usbipd` when the distribution ships a systemd
unit. If no unit is available, start the exporter manually before issuance:

```bash
sudo usbipd -D
```

List and bind only approved devices:

```bash
usbip list -l
sudo usbip bind -b <target-usb-busid>
sudo usbip bind -b <hsm-busid>
```

Use host firewall rules to allow the USB/IP service only from trusted `provcont`
addresses.

## Lab Requirements

The libvirt lab should run `provcont` with q35 and an xHCI controller. The
`infra/Vagrantfile` configures this for libvirt machines.

The `mkosi-esp-project` role installs the Linux-side USB/IP tooling on
`provcont`, including `usbip` and the kernel package needed for `vhci-hcd`.
When `mkosi_esp_usbip_enabled` is true, the role loads `vhci-hcd`, checks the
remote exports, enforces the configured allow-list, attaches the devices, and
settles udev before build/sign/write tasks continue.

Set the USB/IP variables for the run:

```yaml
mkosi_esp_usbip_enabled: true
mkosi_esp_usbip_remote_host: "<windows-host-ip-reachable-from-provcont>"
mkosi_esp_usbip_trusted_hosts:
  - "<windows-host-ip-reachable-from-provcont>"
mkosi_esp_usbip_require_device_ids: true
mkosi_esp_usbip_reject_unknown_exports: true
mkosi_esp_usbip_allowed_devices:
  - name: "ADATA USB Flash Drive"
    busid: "9-3"
    vendor: "125f"
    product: "dd1b"
    serial: "27817200902600C3"
  - name: "YubiKey OTP+FIDO+CCID"
    busid: "9-4"
    vendor: "1050"
    product: "0407"
```

Confirm the remote host from `provcont` before a destructive issuance run:

```bash
sudo /usr/sbin/usbip list -r <windows-host-ip>
sudo /usr/sbin/usbip port
lsblk -o NAME,PATH,MODEL,SERIAL,SIZE,TYPE,TRAN,RM,HOTPLUG,MOUNTPOINTS
gpg --card-status
```

The expected shape is that the target USB appears as a removable USB disk with
the physical serial, and the HSM appears to GPG or the vendor tooling. If the
Windows exporter advertises extra devices, stop and unbind them before
continuing; the role should reject unexpected remote exports when
`mkosi_esp_usbip_reject_unknown_exports` is enabled.

## Issuance Flow

1. Operator triggers the build on `provcont`.
2. Operator plugs in the target USB and HSM on the Windows workstation.
3. Operator binds the exact bus IDs with `usbipd bind`.
4. Ansible verifies the Windows host is trusted, rejects unexpected exports, and
   imports only allow-listed devices into `provcont` over USB/IP.
5. The role signs build provenance, media issuance, and final post-write records.
6. The role writes only after the exact target path confirmation matches.

For interactive HSM signing during development, use a real operator terminal so
pinentry is visible:

```bash
cd infra
scripts/sign-provcont-installer-provenance.sh
```

The helper runs GPG on `provcont`, not on WSL or Windows. It signs
`SHA256SUMS`, the build manifest, the media issuance record, and the final
media-write record in place under `/srv/mkosi-artifacts/<project-name>/`.

`provcont` must already know the public OpenPGP certificate for the HSM signing
key. An OpenPGP card exposes fingerprints and private-key operations, but it
does not reliably provide the full public certificate by itself. For production,
store a public-key URL on the card and use
`mkosi_esp_artifact_signing_public_key_source: card-url`, or provision the key
from a controlled URL or repository trust-bundle file. Do not export the public
key ad hoc from Windows GPG and copy it into `provcont` during issuance.

Avoid the nested chain of Windows to WSL to libvirt USB hostdev for issuance.
That path can expose USB identity while still failing to settle USB mass storage
as a block device. It is useful only as a debugging comparison, not as the normal
operator ceremony.
