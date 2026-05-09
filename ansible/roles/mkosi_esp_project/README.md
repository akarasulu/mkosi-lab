# mkosi_esp_project

Create a mkosi project and build a raw FAT32 EFI System Partition image that
contains the generated UKI at `EFI/BOOT/BOOTX64.EFI`.

The role intentionally keeps credentials out of defaults. If an image root
password is needed, provide it explicitly through `mkosi_esp_root_password`, an
encrypted file referenced by `mkosi_esp_root_password_file`, or the environment
variable named by `mkosi_esp_root_password_env`.

The first implementation is local to this repository. It can later be migrated
into the nested collection after the workflow settles.
