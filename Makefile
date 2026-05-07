SHELL := /bin/bash

LIBVIRT_URI ?= qemu:///system
DOMAIN ?= pe-uki-lab_default

UKI ?= mkosi.output/pe-uki-lab.efi
ESP_IMAGE ?= /var/lib/libvirt/images/pe-uki-lab-esp.img
ESP_SIZE ?= 1G
ESP_LABEL ?= LABUKIESP
ESP_BOOT_FILE ?= ::/EFI/BOOT/BOOTX64.EFI

.PHONY: build mkosi-build esp prepare-esp check-domain-stopped up down destroy ssh console status clean

build: mkosi-build esp

mkosi-build:
	sudo mkosi -f build

esp: check-domain-stopped prepare-esp $(UKI)
	sudo mkfs.vfat -F 32 -n $(ESP_LABEL) $(ESP_IMAGE)
	sudo mmd -i $(ESP_IMAGE) ::/EFI
	sudo mmd -i $(ESP_IMAGE) ::/EFI/BOOT
	sudo mcopy -i $(ESP_IMAGE) -o $(UKI) $(ESP_BOOT_FILE)
	sudo mdir -i $(ESP_IMAGE) ::/EFI/BOOT

prepare-esp:
	@if [ ! -e "$(ESP_IMAGE)" ]; then \
		echo "Creating $(ESP_IMAGE) ($(ESP_SIZE))"; \
		sudo mkdir -p "$$(dirname "$(ESP_IMAGE)")"; \
		sudo truncate -s "$(ESP_SIZE)" "$(ESP_IMAGE)"; \
	fi

check-domain-stopped:
	@state="$$(virsh -c "$(LIBVIRT_URI)" domstate "$(DOMAIN)" 2>/dev/null || true)"; \
	if [ -n "$$state" ] && [ "$$state" != "shut off" ]; then \
		echo "$(DOMAIN) is '$$state'; halt it before rewriting $(ESP_IMAGE)." >&2; \
		exit 1; \
	fi

up:
	vagrant up --provider=libvirt

down:
	vagrant halt

destroy:
	vagrant destroy -f

ssh:
	vagrant ssh

console:
	virsh -c $(LIBVIRT_URI) console $(DOMAIN)

status:
	vagrant status
	virsh -c $(LIBVIRT_URI) domblklist $(DOMAIN) || true

clean:
	sudo mkosi clean
