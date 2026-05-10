# Operator USB/IP Process

Use this process when an operator is issuing a physical installer USB from
`provcont` and signing provenance with a local HSM such as a YubiKey. The goal is
to pass the USB device identity into `provcont`, not to expose only a generic
block device.

## Windows Workstation Setup

Install `usbipd-win` on the Windows operator workstation:

```powershell
winget install --id dorssel.usbipd-win -e
```

The installer provides the `usbipd` service and opens the Windows Firewall path
needed for USB/IP. Keep the firewall narrowed to the operator/lab network where
possible; `provcont` only needs TCP access to the Windows USB/IP service.

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

## Lab Requirements

The libvirt lab should run `provcont` with q35 and an xHCI controller. The
`infra/Vagrantfile` configures this for libvirt machines.

The `mkosi_esp_project` role installs the Linux-side USB/IP tooling on
`provcont`, including `usbip` and the kernel package needed for `vhci-hcd`.
When `mkosi_esp_usbip_enabled` is true, the role loads `vhci-hcd`, checks the
remote exports, enforces the configured allow-list, attaches the devices, and
settles udev before build/sign/write tasks continue.

Set the USB/IP variables for the run:

```yaml
mkosi_esp_usbip_enabled: true
mkosi_esp_usbip_remote_host: "<windows-host-ip-reachable-from-provcont>"
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
the physical serial, and the HSM appears to GPG or the vendor tooling.

## Issuance Flow

1. Operator triggers the build on `provcont`.
2. Operator plugs in the target USB and HSM on the Windows workstation.
3. Operator binds the exact bus IDs with `usbipd bind`.
4. Ansible imports only allow-listed devices into `provcont` over USB/IP.
5. The role signs build provenance, media issuance, and final post-write records.
6. The role writes only after the exact target path confirmation matches.

Avoid the nested chain of Windows to WSL to libvirt USB hostdev for issuance.
That path can expose USB identity while still failing to settle USB mass storage
as a block device. It is useful only as a debugging comparison, not as the normal
operator ceremony.
