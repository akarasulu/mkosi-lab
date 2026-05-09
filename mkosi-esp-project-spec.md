# Requirements for ESP builder role

## Purpose

Create a reusable Ansible role that stamps out mkosi-based projects on
`provcont` and builds bootable EFI System Partition images from them.

The core output is a raw FAT32 ESP image containing a Unified Kernel Image at
the removable-media default boot path:

```text
EFI/BOOT/BOOTX64.EFI
```

The role is for a provisioning controller that creates various bootable USB
images. A Vagrant box or libvirt test wrapper may be useful for human testing,
but it is not the primary product of this role.

## Goals

- Create minimal, repeatable mkosi project directories on `provcont`.
- Build a UKI with `mkosi`.
- Default to Debian trixie for generated images, with a controlled fallback to
  Debian bookworm when trixie is unavailable in the target environment.
- Create a FAT32 ESP partition image sized from the generated UKI, with a
  configurable amount of extra space. The default extra space should be 10 MiB.
- Copy the UKI into the ESP as `EFI/BOOT/BOOTX64.EFI`.
- Store build artifacts in predictable project-local or controller-wide paths.
- Keep project definitions variable-driven so multiple USB images can be
  generated from the same role.
- Allow optional overlay content through `mkosi.extra`.
- Install the host-side dependencies required to create projects, build UKIs,
  format ESP images, and copy files into FAT images.
- Keep the role useful without requiring Python packaging, `uv`, or Vagrant.

## Non-Goals

- Vagrant box creation is not part of the core build path. It may be added as
  an optional feature that is off by default, or as a separate role if that
  keeps the ESP builder cleaner.
- The role does not need to manage libvirt domains.
- The role does not produce a whole-disk image with a partition table. The
  primary artifact is the ESP filesystem image itself: one FAT32 ESP image with
  the UKI inside it, plus optional support files such as certificates later.
- The role does not implement the separate machine-registration image builder.
  That future builder is expected to use a remastered image with PKCS#11-based
  LUKS unlock, register machines, and extract local hardware information. That
  lifecycle belongs outside this ESP project builder.
- The role does not solve production signing or Secure Boot enrollment in the
  first version.
- The role does not bake cleartext image credentials into defaults. Secure
  bootstrap provenance matters more than convenience here; any image password
  or secret material must be provided explicitly through a protected source.
- The role does not need to manage USB device flashing directly in the first
  version. Writing to physical media should be an explicit later step.

## Minimal project shape

Each generated project should be understandable on disk without knowing
Ansible internals.

```text
/srv/mkosi-projects/<project-name>/
  mkosi.conf
  mkosi.extra/
  mkosi.cache/
  mkosi.output/
```

Suggested controller-wide artifact location:

```text
/srv/mkosi-artifacts/<project-name>/
  <project-name>.esp.raw
  <project-name>.efi
  <project-name>.mkosi-build.log
```

The artifact directory may be project-local instead if that is simpler:

```text
/srv/mkosi-projects/<project-name>/artifacts/
  <project-name>.esp.raw
  <project-name>.efi
```

The role should make this path configurable.

The default should use the split above:

```text
/srv/mkosi-projects
/srv/mkosi-artifacts
```

## Role name

Suggested role name:

```text
mkosi_esp_project
```

Suggested repository layout:

```text
roles/mkosi_esp_project/
  defaults/main.yml
  tasks/main.yml
  handlers/main.yml
  templates/
    mkosi.conf.j2
  README.md
```

Additional templates can be added later for optional payload services, network
configuration, or first-boot scripts.

## Main workflow

The role should support two closely related operations:

1. Create or update the mkosi project.
2. Build the UKI and ESP image.

These can be controlled by booleans so callers can create projects without
building them every time.

```yaml
mkosi_esp_project_create: true
mkosi_esp_project_build: true
```

### Create or update project

Tasks:

- Ensure host packages needed for building are installed when requested.
- Create the project directory.
- Create `mkosi.extra` and common child directories when requested.
- Render `mkosi.conf`.
- Optionally copy or template overlay files into `mkosi.extra`.
- Ensure artifact and cache directories exist.
- Initialize each project as a Git repository when project Git tracking is
  enabled.
- Write a project `.gitignore` that excludes build byproducts while allowing
  configuration and overlay source files to be tracked.
- Optionally create an initial commit after rendering the project files.

### Project Git tracking

Each generated mkosi project should be versioned with Git by default so changes
to `mkosi.conf`, overlay files, and project metadata can be audited over time.
The Git repository belongs to the generated project directory, not to the
artifact directory.

The role should track source inputs such as:

```text
mkosi.conf
mkosi.extra/
README.md
```

The role should not track build byproducts such as:

```text
mkosi.cache/
mkosi.output/
artifacts/
*.esp.raw
*.efi
*.img
*.qcow2
*.box
```

Suggested controls:

```yaml
mkosi_esp_project_git_enabled: true
mkosi_esp_project_git_initial_commit: true
mkosi_esp_project_git_commit_message: "Initialize mkosi ESP project"
```

### Build UKI

Tasks:

- Run `mkosi -f build` from the project directory.
- Locate the expected UKI output.
- Copy or preserve the UKI in the artifact directory.
- Capture mkosi build output in the artifact directory when build logging is
  enabled so long package/image phases can be inspected while preserving
  provenance.

The expected UKI output defaults to:

```text
mkosi.output/<project-name>.efi
```

Make sure not to version-control build byproducts.

### Build ESP image

Tasks:

- Calculate the generated UKI size.
- Calculate the ESP image size as `UKI size + mkosi_esp_extra_size`, rounded up
  to a filesystem-friendly boundary.
- Create or recreate a raw ESP image file using that calculated size.
- Format it as FAT32.
- Create `EFI` and `EFI/BOOT` directories inside the image.
- Copy the UKI to `EFI/BOOT/BOOTX64.EFI`.
- Optionally list or verify the resulting ESP contents.

The implementation can use the same tooling as the current lab:

```text
truncate
mkfs.vfat
mmd
mcopy
mdir
```

The ESP image is a partition image, not a full disk image. It can later be
written into a USB partition or wrapped by another workflow, but the core role
should focus on producing the FAT32 ESP artifact.

## Required host packages

The first version should support Debian on `provcont`. Package names should be
variables, but defaults can be Debian-oriented.

```yaml
mkosi_esp_host_packages:
  - mkosi
  - systemd-boot-efi
  - qemu-utils
  - dosfstools
  - mtools
  - binutils
  - file
  - ca-certificates
  - git
  - linux-image-amd64
```

Depending on the generated image content, projects may also need packages such
as:

```yaml
  - curl
  - gnupg
  - openssl
  - python3
  - sbsigntool
```

The role should install all packages required by the default workflow when
`mkosi_esp_install_host_packages` is true. At minimum that means the packages
needed to run `mkosi`, create a UKI, format a FAT ESP image, and manipulate the
FAT image from Ansible tasks. Optional feature packages should be controlled by
variables instead of being hidden assumptions.

## Default role variables

Initial defaults:

```yaml
mkosi_esp_project_name: rescue-usb
mkosi_esp_project_root: /srv/mkosi-projects
mkosi_esp_artifact_root: /srv/mkosi-artifacts
mkosi_esp_project_owner: "{{ ansible_user | default(ansible_user_id) }}"
mkosi_esp_project_group: "{{ mkosi_esp_project_owner }}"

mkosi_esp_project_create: true
mkosi_esp_project_build: true
mkosi_esp_install_host_packages: true
mkosi_esp_project_git_enabled: true
mkosi_esp_project_git_initial_commit: true
mkosi_esp_project_git_commit_message: "Initialize mkosi ESP project"
mkosi_esp_project_git_commit_on_change: true
mkosi_esp_project_git_sign_commits: false
mkosi_esp_project_git_signing_key: ""

mkosi_esp_distribution: debian
mkosi_esp_release: trixie
mkosi_esp_release_fallback: bookworm
mkosi_esp_allow_release_fallback: true
mkosi_esp_architecture: x86-64
mkosi_esp_mirror: http://deb.debian.org/debian

mkosi_esp_output_format: uki
mkosi_esp_legacy_uki_output_format: gpt_ext4
mkosi_esp_output_directory: mkosi.output
mkosi_esp_cache_directory: mkosi.cache
mkosi_esp_extra_trees:
  - mkosi.extra

mkosi_esp_kernel_command_line: console=ttyS0
mkosi_esp_root_password: ""
mkosi_esp_root_password_file: ""
mkosi_esp_root_password_env: MKOSI_ESP_ROOT_PASSWORD
mkosi_esp_root_shell: /bin/bash

mkosi_esp_image_packages:
  - systemd
  - udev
  - linux-image-amd64
  - kmod
  - dbus
  - login
  - apt
  - iproute2
  - iputils-ping
  - ca-certificates
  - systemd-boot-efi

mkosi_esp_extra_size: 10M
mkosi_esp_size_rounding: 1M
mkosi_esp_label: RESCUE
mkosi_esp_image_name: "{{ mkosi_esp_project_name }}.esp.raw"
mkosi_esp_boot_file: ::/EFI/BOOT/BOOTX64.EFI
mkosi_esp_build_log_enabled: true
mkosi_esp_build_log_name: "{{ mkosi_esp_project_name }}.mkosi-build.log"
mkosi_esp_manifest_enabled: true
mkosi_esp_manifest_name: "{{ mkosi_esp_project_name }}.manifest.json"
mkosi_esp_checksums_name: SHA256SUMS
mkosi_esp_vagrant_box_enabled: false
```

When `mkosi_esp_allow_release_fallback` is true, implementation should attempt
the requested release first and retry once with `mkosi_esp_release_fallback` if
the build fails for a release-availability reason. The retry should be explicit
in logs and in the artifact manifest.

Project Git support should initialize the generated project repository, write
the project `.gitignore`, stage source changes as the role updates files, and
commit those changes when `mkosi_esp_project_git_commit_on_change` is true.
When `mkosi_esp_project_git_sign_commits` is true, commits should use
`git commit -S`; if `mkosi_esp_project_git_signing_key` is set, configure the
project-local `user.signingkey` before committing. Signing is optional because
the controller may not always have an unlocked private key, but the role should
make the provenance path first-class when the key is made available.

Generated projects should be owned by `mkosi_esp_project_owner` and
`mkosi_esp_project_group`, defaulting to the connecting controller user rather
than root. Git operations should run as that owner so `git log`, diffs, and
future provenance checks work without requiring `sudo` or global
`safe.directory` exceptions.

The default root password is intentionally empty and should be omitted from
`mkosi.conf` unless a protected source provides it. Acceptable sources are an
encrypted repository file managed with git-crypt, an environment variable such
as `MKOSI_ESP_ROOT_PASSWORD`, or a file path supplied from the controller
environment via `mkosi_esp_root_password_file`. Security first is a mantra for
this project because the whole point is to bootstrap systems securely with
provenance; examples and defaults should reflect that.

Derived paths:

```yaml
mkosi_esp_project_dir: "{{ mkosi_esp_project_root }}/{{ mkosi_esp_project_name }}"
mkosi_esp_artifact_dir: "{{ mkosi_esp_artifact_root }}/{{ mkosi_esp_project_name }}"
mkosi_esp_uki_path: "{{ mkosi_esp_project_dir }}/{{ mkosi_esp_output_directory }}/{{ mkosi_esp_project_name }}.efi"
mkosi_esp_uki_artifact_path: "{{ mkosi_esp_artifact_dir }}/{{ mkosi_esp_project_name }}.efi"
mkosi_esp_image_path: "{{ mkosi_esp_artifact_dir }}/{{ mkosi_esp_image_name }}"
mkosi_esp_build_log_path: "{{ mkosi_esp_artifact_dir }}/{{ mkosi_esp_build_log_name }}"
mkosi_esp_manifest_path: "{{ mkosi_esp_artifact_dir }}/{{ mkosi_esp_manifest_name }}"
mkosi_esp_checksums_path: "{{ mkosi_esp_artifact_dir }}/{{ mkosi_esp_checksums_name }}"
mkosi_esp_size: "{{ mkosi_esp_uki_size + mkosi_esp_extra_size }}"
```

The implementation may calculate `mkosi_esp_size` during the build rather than
declaring it directly in defaults. The important requirement is that the ESP is
based on the actual UKI size plus configurable headroom, not a large fixed
default such as 384 MiB.

The role should detect the installed mkosi version and render compatible config
when needed. Debian bookworm's mkosi 14 does not support `Format=uki`,
`Architecture=x86-64`, `CacheDirectory=`, `ExtraTrees=`, `RootPassword=`, or
space-separated package lists in the same way newer mkosi does. For that
version, the role may render a bootable `gpt_ext4` image with
`SplitArtifacts=yes`, use `x86_64`, `Cache=`, repeated `ExtraTree=`, and
comma-separated `Packages=`, then locate the generated split `.efi` artifact
and package that UKI into the standalone ESP image.

## `mkosi.conf` template

The first version can render a compact `mkosi.conf` like this:

```ini
[Distribution]
Distribution={{ mkosi_esp_distribution }}
Release={{ mkosi_esp_release }}
Architecture={{ mkosi_esp_architecture }}
Mirror={{ mkosi_esp_mirror }}

[Output]
Format={{ mkosi_esp_output_format }}
Output={{ mkosi_esp_project_name }}
OutputDirectory={{ mkosi_esp_output_directory }}

[Build]
CacheDirectory={{ mkosi_esp_cache_directory }}

[Content]
ExtraTrees={{ mkosi_esp_extra_trees | join(' ') }}
Packages={% for package in mkosi_esp_image_packages %}{% if loop.first %}{{ package }}{% else %}
         {{ package }}{% endif %}{% endfor %}
RootPassword={{ mkosi_esp_root_password }}
RootShell={{ mkosi_esp_root_shell }}
KernelCommandLine={{ mkosi_esp_kernel_command_line }}
```

The template should omit optional values when they are empty rather than
writing invalid mkosi configuration.

In particular, `RootPassword=` must not be rendered unless the value has been
explicitly supplied through `mkosi_esp_root_password`,
`mkosi_esp_root_password_file`, or `mkosi_esp_root_password_env`.

## Example playbook

```yaml
---
- name: Create and build mkosi ESP projects
  hosts: provcont
  become: true
  roles:
    - role: mkosi_esp_project
      vars:
        mkosi_esp_project_name: rescue-usb
        mkosi_esp_release: trixie
        mkosi_esp_label: RESCUE
```

## Example multi-project inventory data

The role can be called repeatedly from a loop when the controller needs to
build several bootable USB variants.

```yaml
mkosi_esp_projects:
  - name: rescue-usb
    label: RESCUE
    packages:
      - systemd
      - udev
      - linux-image-amd64
      - iproute2
      - openssh-server
  - name: installer-usb
    label: INSTALL
    packages:
      - systemd
      - udev
      - linux-image-amd64
      - curl
      - ca-certificates
```

A wrapper playbook can include the role once per project:

```yaml
---
- name: Build all mkosi ESP images
  hosts: provcont
  become: true
  tasks:
    - name: Build configured ESP project
      ansible.builtin.include_role:
        name: mkosi_esp_project
      vars:
        mkosi_esp_project_name: "{{ item.name }}"
        mkosi_esp_label: "{{ item.label }}"
        mkosi_esp_image_packages: "{{ item.packages }}"
      loop: "{{ mkosi_esp_projects }}"
```

## Idempotence expectations

The role should be idempotent for project creation:

- Directories are created only when missing.
- `mkosi.conf` changes only when inputs change.
- Overlay files change only when their source content changes.

The build phase is allowed to be intentionally rebuild-oriented. A first
version can run `mkosi -f build` whenever `mkosi_esp_project_build` is true.
Later versions can add change detection or a separate `force_build` variable.
When build logging pipes mkosi output through `tee`, the command should use
`pipefail` so mkosi failures still propagate to Ansible.

Suggested controls:

```yaml
mkosi_esp_force_build: true
mkosi_esp_recreate_esp: true
```

If `mkosi_esp_recreate_esp` is true, the ESP image may be reformatted on each
build. This is acceptable because the ESP is an output artifact, not user data.
If the Vagrant feature is built into this role, Vagrant box recreation must be
explicit and repeatable: remove the previous generated box for the project and
add the newly built box.

## Safety expectations

- The role must not write to physical USB block devices by default, especially system disks.
- Any future physical-device flashing task must require an explicit variable
  such as `mkosi_esp_flash_device`.
- The role must not delete project directories unless explicitly requested.
- Recreating the ESP artifact is allowed only inside the configured artifact
  path.
- Package installation and builds are expected to run with privilege on
  `provcont` as the `infra` user.

## Acceptance checks

A successful run should leave these files on `provcont`:

```text
/srv/mkosi-projects/<project-name>/mkosi.conf
/srv/mkosi-projects/<project-name>/.gitignore
/srv/mkosi-projects/<project-name>/mkosi.output/<project-name>.efi
/srv/mkosi-artifacts/<project-name>/<project-name>.efi
/srv/mkosi-artifacts/<project-name>/<project-name>.esp.raw
/srv/mkosi-artifacts/<project-name>/<project-name>.mkosi-build.log
/srv/mkosi-artifacts/<project-name>/<project-name>.manifest.json
/srv/mkosi-artifacts/<project-name>/SHA256SUMS
```

The ESP image should contain:

```text
EFI/BOOT/BOOTX64.EFI
```

Useful verification commands:

```bash
file /srv/mkosi-artifacts/<project-name>/<project-name>.esp.raw
mdir -i /srv/mkosi-artifacts/<project-name>/<project-name>.esp.raw ::/EFI/BOOT
tail -40 /srv/mkosi-artifacts/<project-name>/<project-name>.mkosi-build.log
cd /srv/mkosi-artifacts/<project-name> && sha256sum -c SHA256SUMS
python3 -m json.tool /srv/mkosi-artifacts/<project-name>/<project-name>.manifest.json
```

Expected `mdir` output should include:

```text
BOOTX64  EFI
```

The first implementation should run a real build as part of verification, not
only Ansible syntax checks. A useful minimum is:

```bash
ansible-playbook --syntax-check <playbook-that-calls-the-role>.yml
ansible-playbook <playbook-that-calls-the-role>.yml
file /srv/mkosi-artifacts/<project-name>/<project-name>.esp.raw
mdir -i /srv/mkosi-artifacts/<project-name>/<project-name>.esp.raw ::/EFI/BOOT
```

The role now lives in the sibling `nested` collection checkout under
`../nested/roles/mkosi_esp_project`. The local validation playbook calls the
role by its short name while `ANSIBLE_ROLES_PATH` points at that collection
checkout.

## Relationship to existing `mkosi-lab`

The current `mkosi-lab` repository already demonstrates the core build chain:

```text
mkosi.conf
mkosi.extra/
mkosi -f build
FAT ESP image
EFI/BOOT/BOOTX64.EFI
```

The existing Makefile also packages the ESP into a Vagrant box. That part is
useful for human boot testing, but it should remain outside the core role or
incorporated as an optional feature disabled by default.

The existing `uv_mkosi_project_baseline` role is a developer-project
bootstrapper. The new `mkosi_esp_project` role should be simpler and more
server-oriented: it creates buildable mkosi ESP projects on `provcont` and
emits bootable ESP artifacts.

The implementation lives in the sibling `nested` collection checkout while this
repository keeps the mkosi-lab-specific validation playbooks and Make targets.

Existing repo pieces that are generally useful to borrow:

- The current root `mkosi.conf` and
  `ansible/roles/uv_mkosi_project_baseline/templates/mkosi.conf.j2` show the
  compact mkosi configuration shape that already works in this lab.
- `ansible/roles/uv_mkosi_project_baseline/defaults/main.yml` contains a known
  working Debian trixie package set for mkosi, UKI generation, FAT tooling, and
  basic rescue/debug networking tools.
- The current `mkosi.extra/etc/systemd/network` files and matching baseline
  templates are useful optional overlay examples for DHCP or static networking.
- The existing systemd service, sysusers, sudoers, and setup-script overlays are
  useful examples for future payload images, but the first ESP role should keep
  them optional instead of making Vagrant or a default login user part of the
  core output.
- The existing Makefile demonstrates the ESP creation flow and can guide the
  Ansible tasks for sizing, formatting, and copying the UKI into
  `EFI/BOOT/BOOTX64.EFI`.

## Possible later features

- Optional Vagrant/libvirt/virtualbox test wrapper for humans.
- Secure Boot signing support with configurable signing keys, certificate
  enrollment artifacts, and a clear unsigned/signed artifact naming convention.
- Optional encrypted-root image support using LUKS. The role should be able to
  pass the required mkosi settings, include the initramfs tools needed for early
  unlock, and expose variables for either passphrase-based development images or
  TPM2/FIDO2-bound unlock flows.
- Optional dm-verity support for read-only or measured root images. Generated
  artifacts should keep the root hash, verity metadata, and kernel command-line
  fragments together so a consuming boot flow can verify the image reproducibly.
- Optional measured-boot integration for UKIs, including PCR policy generation,
  systemd-stub metadata, and manifest entries that make it clear which inputs
  affect the resulting measurements.
- Kernel command-line extension hooks for project-specific boot parameters such
  as root device selection, verity flags, LUKS options, console settings, and
  debug toggles.
- Support for additional mkosi image outputs alongside the ESP, such as a root
  disk image, initrd-only artifact, or split `/usr` image when a project needs
  more than a standalone UKI.
- Per-project overlay file trees from Git or local templates.
- A small index page or API on `provcont` to list available generated images.
- Explicit USB flashing task gated by a required device variable.
