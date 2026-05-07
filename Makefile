SHELL := /bin/bash

LIBVIRT_URI ?= qemu:///system
DOMAIN ?= pe-uki-lab_default

BOX_NAME ?= nested/uki-boot
BOX_VERSION ?= 0.1.0
BOX_PROVIDER ?= libvirt
BOX_BUILD_DIR ?= .vagrant/uki-box
BOX_FILE ?= $(BOX_BUILD_DIR)/nested-uki-boot.box
BOX_CATALOG ?= $(BOX_BUILD_DIR)/metadata-catalog.json
BOX_DISK ?= $(BOX_BUILD_DIR)/box.img

UKI ?= mkosi.output/pe-uki-lab.efi
ESP_IMAGE ?= $(BOX_BUILD_DIR)/pe-uki-lab-esp.raw
ESP_SIZE ?= 384M
ESP_LABEL ?= LABUKIESP
ESP_BOOT_FILE ?= ::/EFI/BOOT/BOOTX64.EFI

.PHONY: build run mkosi-build esp prepare-esp box register-box remove-box-volume check-domain-stopped up down destroy ssh console status clean

build: destroy mkosi-build esp box register-box

run: build up

mkosi-build:
	sudo mkosi -f build

esp: check-domain-stopped prepare-esp $(UKI)
	mkfs.vfat -F 32 -n $(ESP_LABEL) $(ESP_IMAGE)
	mmd -i $(ESP_IMAGE) ::/EFI
	mmd -i $(ESP_IMAGE) ::/EFI/BOOT
	mcopy -i $(ESP_IMAGE) -o $(UKI) $(ESP_BOOT_FILE)
	mdir -i $(ESP_IMAGE) ::/EFI/BOOT

prepare-esp:
	@mkdir -p "$(BOX_BUILD_DIR)"
	@if [ ! -e "$(ESP_IMAGE)" ]; then \
		echo "Creating $(ESP_IMAGE) ($(ESP_SIZE))"; \
		truncate -s "$(ESP_SIZE)" "$(ESP_IMAGE)"; \
	fi

box: esp
	rm -f "$(BOX_DISK)" "$(BOX_FILE)" "$(BOX_CATALOG)"
	qemu-img convert -f raw -O qcow2 "$(ESP_IMAGE)" "$(BOX_DISK)"
	printf '%s\n' '{"provider":"$(BOX_PROVIDER)","architecture":"amd64","disks":[{"format":"qcow2","path":"box.img"}]}' > "$(BOX_BUILD_DIR)/metadata.json"
	printf '%s\n' 'Vagrant.configure("2") do |config|' \
		'  config.vm.synced_folder ".", "/vagrant", disabled: true' \
		'  config.vm.provider :libvirt do |libvirt|' \
		'    libvirt.driver = "qemu"' \
		'    libvirt.machine_type = "q35"' \
		'  end' \
		'end' > "$(BOX_BUILD_DIR)/Vagrantfile"
	tar -C "$(BOX_BUILD_DIR)" -czf "$(BOX_FILE)" metadata.json Vagrantfile box.img
	box_url="file://$$(pwd)/$(BOX_FILE)"; \
		printf '%s\n' \
		'{"name":"$(BOX_NAME)","versions":[{"version":"$(BOX_VERSION)","providers":[{"name":"$(BOX_PROVIDER)","url":"'"$$box_url"'"}]}]}' \
		> "$(BOX_CATALOG)"

register-box: box remove-box-volume
	vagrant box remove "$(BOX_NAME)" --provider "$(BOX_PROVIDER)" --all --force 2>/dev/null || true
	vagrant box add --force "$(BOX_CATALOG)"

remove-box-volume:
	@virsh -c "$(LIBVIRT_URI)" vol-list default --name 2>/dev/null | \
		awk '/^nested-VAGRANTSLASH-uki-boot_vagrant_box_image_/ { print }' | \
		while read -r volume; do \
			echo "Removing stale libvirt box volume $$volume"; \
			virsh -c "$(LIBVIRT_URI)" vol-delete "$$volume" --pool default >/dev/null; \
		done

check-domain-stopped:
	@state="$$(virsh -c "$(LIBVIRT_URI)" domstate "$(DOMAIN)" 2>/dev/null || true)"; \
	if [ -n "$$state" ] && [ "$$state" != "shut off" ]; then \
		echo "$(DOMAIN) is '$$state'; halt it before rewriting $(ESP_IMAGE)." >&2; \
		exit 1; \
	fi

up:
	vagrant up --provider=libvirt

down:
	@state="$$(virsh -c "$(LIBVIRT_URI)" domstate "$(DOMAIN)" 2>/dev/null || true)"; \
	if [ "$$state" = "running" ] || [ "$$state" = "paused" ]; then \
		vagrant halt; \
	else \
		echo "$(DOMAIN) is not running; nothing to halt."; \
	fi

destroy:
	@state="$$(virsh -c "$(LIBVIRT_URI)" domstate "$(DOMAIN)" 2>/dev/null || true)"; \
	if [ -n "$$state" ]; then \
		vagrant destroy -f; \
	else \
		echo "$(DOMAIN) is not created; nothing to destroy."; \
	fi

ssh:
	vagrant ssh

console:
	virsh -c $(LIBVIRT_URI) console $(DOMAIN)

status:
	vagrant status
	virsh -c $(LIBVIRT_URI) domblklist $(DOMAIN) || true

clean:
	sudo mkosi clean
