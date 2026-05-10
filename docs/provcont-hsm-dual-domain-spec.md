# Provcont HSM Dual-Domain Enrollment Spec

## Purpose

Define how `provcont` uses one or more HSMs to separate enrollment authority
from admin/operator provenance signing.

The central design is to use two cryptographic domains:

1. Enrollment authority domain:
   A CA key signs HSM enrollment records, machine registration records, and
   registration image manifests.
2. Admin/operator provenance domain:
   An OpenPGP key signs issuance records, media write records, and other
   operator-approved provenance artifacts.

For small deployments, both domains may live on one physical YubiKey by using
PIV for the enrollment CA and OpenPGP for the admin/operator identity. For
stronger production separation, use separate HSMs.

## Background

A YubiKey OpenPGP applet is not a general-purpose vault for many independent
GPG identities. It is best modeled as one OpenPGP identity with three private
key roles:

1. Signature
2. Encryption/decryption
3. Authentication

The YubiKey PIV application is a separate smart-card application. It exposes
multiple certificate/key slots and is accessible through PKCS#11. PIV slot `9c`
is intended for digital signatures and requires PIN verification immediately
before signing. Slot `9a` is for authentication, slot `9d` for key management,
and slot `9e` for card authentication. YubiKey 4 and 5 devices also expose
retired key-management slots and attestation slot `f9`.

This separation lets one physical HSM serve two different roles without forcing
two OpenPGP identities onto the same OpenPGP applet.

## Trust Roles

### Provcont Enrollment CA

The enrollment CA is the authority that turns inspected devices and machines
into trusted registry records.

Production storage:

- PKCS#11-backed key in a dedicated HSM, or
- YubiKey PIV slot, preferably `9c` for digital signature.

Lab-only storage:

- File-backed CA key, clearly labeled non-production.

The CA signs:

- HSM enrollment records.
- Machine registration records after admin approval.
- Machine registration image manifests.
- Policy snapshots when useful.

### Admin/Operator HSM

The admin/operator HSM signs human-approved provenance events.

Storage:

- OpenPGP key generated on, or enrolled onto, the HSM.

The admin/operator key signs:

- Machine registration records before CA countersignature.
- Media issuance records.
- Post-write media manifests.
- Install attestations when policy requires admin participation.

## Enrollment Ceremony

The first-time HSM enrollment ceremony creates trust for a new admin/operator
HSM.

1. Admin presents a new HSM to `provcont`.
2. `provcont` imports the HSM through the configured path:
   direct attachment, VM passthrough, or USB/IP.
3. `provcont` inspects HSM facts:
   USB identity, YubiKey serial, OpenPGP card serial, application ID, firmware,
   enabled interfaces, and existing fingerprints.
4. `provcont` generates the OpenPGP admin/operator key on the HSM, or imports
   a policy-approved existing HSM-backed OpenPGP identity.
5. `provcont` creates the full OpenPGP public certificate during enrollment.
6. `provcont` publishes the public certificate to controlled key storage.
7. `provcont` creates an HSM enrollment record.
8. The enrollment CA signs the enrollment record.
9. `provcont` stores the record and signature in the enrollment registry.

The public certificate must be generated or obtained on `provcont` from a
controlled source. Do not export it ad hoc from Windows or another workstation
during production enrollment.

## Enrollment Record

The enrollment record should be JSON and include at least:

```json
{
  "kind": "provcont-hsm-enrollment",
  "version": 1,
  "operator": {
    "id": "alice",
    "roles": ["installer-issuer"]
  },
  "hsm": {
    "transport": "usbip",
    "usb_vendor_id": "1050",
    "usb_product_id": "0407",
    "yubikey_serial": "18349797",
    "openpgp_card_serial": "000618349797",
    "openpgp_application_id": "D2760001240103040006183497970000"
  },
  "openpgp": {
    "primary_fingerprint": "...",
    "signing_subkey_fingerprint": "...",
    "public_certificate_sha256": "...",
    "public_certificate_path": "keys/<fingerprint>.asc"
  },
  "policy": {
    "requires_pin": true,
    "requires_touch": true
  }
}
```

The enrollment signature should be written beside the record:

```text
enrollments/<operator-id>/<card-serial>.json
enrollments/<operator-id>/<card-serial>.json.sig
```

## Machine Registration Flow

1. `provcont` builds a per-admin headed machine registration image.
2. The image manifest is signed by the enrollment CA.
3. Admin boots the headed image on a target machine.
4. The image probes hardware:
   TPM, firmware, CPU, disks, NICs, platform identifiers, and boot mode.
5. Admin reviews the probed facts.
6. Admin signs the machine record with their enrolled OpenPGP HSM.
7. `provcont` verifies the admin HSM enrollment.
8. `provcont` countersigns the machine record with the enrollment CA.
9. The machine enters the registered inventory.

## Installer Issuance Flow

1. Admin requests an installer for a registered machine.
2. `provcont` builds the installer UKI and ESP.
3. `provcont` generates build provenance:
   manifest, checksums, logs, and artifact hashes.
4. Admin presents target USB and admin HSM.
5. `provcont` resets stale USB/IP state and imports only allow-listed devices.
6. `provcont` verifies target USB identity and admin HSM enrollment.
7. `provcont` creates a media issuance record.
8. Admin HSM signs the issuance record on `provcont`.
9. `provcont` writes the ESP to the USB as a GPT EFI System Partition.
10. `provcont` verifies `EFI/BOOT/BOOTX64.EFI`.
11. `provcont` creates a post-write media manifest.
12. Admin HSM signs the post-write media manifest on `provcont`.

Generated artifacts and provenance records stay on `provcont`. Windows or other
operator workstations may export USB devices, but they must not generate or
modify provenance-critical material.

## Small Deployment Model

For home or small-site deployments, one YubiKey can hold both roles:

1. PIV slot for the enrollment CA.
2. OpenPGP applet for the admin/operator provenance identity.

This is acceptable for low-scale deployments when documented as a combined
authority/operator HSM. It is weaker than separate physical HSMs because loss or
compromise affects both roles, but it preserves role separation at the
cryptographic interface level.

## Production Model

For production, prefer:

1. Dedicated CA HSM controlled by the provisioning authority.
2. Separate admin/operator HSMs for issuance signatures.
3. Explicit enrollment approvals.
4. Published public certificates from controlled `provcont` storage.
5. Signed enrollment, machine, issuance, write, and install records.

## Implementation Requirements

1. Add enrollment registry directories under `provcont` control.
2. Add file-backed CA support for lab tests.
3. Add PKCS#11/PIV CA support for production.
4. Add OpenPGP HSM enrollment tasks.
5. Add public certificate publication and fingerprint verification.
6. Make issuance refuse unregistered HSMs.
7. Add USB/IP reset before import:
   detach stale ports, restart `pcscd`, kill stale `scdaemon`/`gpg-agent`, load
   `vhci-hcd`, then import only allow-listed devices.
8. Add visible operator terminal flows for PIN entry and touch prompts.

## References

- Yubico documents PIV as a separate application that exposes RSA/ECC
  sign/decrypt operations through interfaces such as PKCS#11.
- Yubico documents PIV slots including `9a`, `9c`, `9d`, `9e`, retired key
  slots, and attestation slot `f9`.
- Yubico documents OpenPGP support as three subkeys for signature, encryption,
  and authentication under one OpenPGP identity.
