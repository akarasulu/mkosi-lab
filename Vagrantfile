require "fileutils"

Vagrant.configure("2") do |config|
  config.vm.box = "nested/uki-boot"
  config.vm.box_check_update = false

  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.ssh.username = "vagrant"
  config.ssh.insert_key = false

  config.vm.provider :libvirt do |libvirt|
    ovmf_loader = [
      "/usr/share/OVMF/OVMF_CODE_4M.fd",
      "/usr/share/edk2/x64/OVMF_CODE.4m.fd",
      "/usr/share/edk2/x64/OVMF_CODE.fd",
      "/usr/share/OVMF/OVMF_CODE.fd"
    ].find { |path| File.exist?(path) }

    ovmf_vars_template = [
      "/usr/share/OVMF/OVMF_VARS_4M.fd",
      "/usr/share/edk2/x64/OVMF_VARS.4m.fd",
      "/usr/share/edk2/x64/OVMF_VARS.fd",
      "/usr/share/OVMF/OVMF_VARS_4M.snakeoil.fd",
      "/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
    ].find { |path| File.exist?(path) }

    box_name = config.vm.box.gsub(/[^A-Za-z0-9_.-]/, "_")
    ovmf_vars = "/tmp/pe-uki-lab_#{box_name}_OVMF_VARS_4M.fd"
    if ovmf_vars_template && !File.exist?(ovmf_vars)
      FileUtils.cp(ovmf_vars_template, ovmf_vars)
      FileUtils.chmod(0o666, ovmf_vars)
    end

    wsl = begin
      File.read("/proc/sys/kernel/osrelease").downcase.include?("microsoft")
    rescue
      false
    end

    libvirt.cpus = 2
    libvirt.memory = 2048
    # Keep the management NIC stable. The UKI uses a broad systemd-networkd
    # DHCP match, but stable PCI topology makes debugging less surprising.
    libvirt.management_network_pci_bus = "0x05"
    libvirt.management_network_pci_slot = "0x00"
    libvirt.disk_device = "vda"
    libvirt.disk_bus = "virtio"
    libvirt.boot "hd"

    if wsl
      # WSL2 often lacks /dev/kvm inside the distro. In that environment,
      # q35 + SeaBIOS can hang at "Booting from Hard Disk..." before GRUB.
      libvirt.driver = "qemu"
      libvirt.cpu_model = "host-passthrough"
      libvirt.cpu_fallback = "allow"
      libvirt.machine_type = "q35"
      libvirt.loader = ovmf_loader if ovmf_loader
      libvirt.nvram = ovmf_vars if ovmf_loader && File.exist?(ovmf_vars)
    else
      libvirt.cpu_mode = "host-passthrough"
      libvirt.nested = true
      libvirt.cpu_fallback = "allow"
      libvirt.machine_type = "q35"
      libvirt.loader = ovmf_loader if ovmf_loader
      libvirt.nvram = ovmf_vars if ovmf_loader && File.exist?(ovmf_vars)
    end
  end
end
