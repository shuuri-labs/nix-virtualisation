# QEMU VM Manager

This module provides declarative QEMU VM management with support for base images, blank disk installation, and cloud-init.

## Features

- **Base Image VMs**: Use pre-built base images (converted and cached)
- **Blank Disk VMs**: Create VMs from scratch with installer ISOs
- **Cloud-init Support**: Automatic VM configuration for Linux VMs
- **ISO Mounting**: Mount installer and cloud-init ISOs automatically

## Configuration Examples

### 1. Base Image VM (Traditional)
```nix
virtualisation.qemu.manager = {
  images."ubuntu-22.04" = {
    enable = true;
    source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img";
    sourceSha256 = "...";
    sourceFormat = "qcow2";
  };

  services."ubuntu-server" = {
    enable = true;
    baseImage = "ubuntu-22.04";  # References the image above
    memory = 2048;
    diskSizeGB = 20;
    vncPort = 1;
    hostBridges = [ "br0" ];
  };
};
```

### 2. Blank Disk VM with Installer ISO
```nix
virtualisation.qemu.manager.services."windows-11" = {
  enable = true;
  baseImage = null;                                    # No base image
  diskSizeGB = 80;                                    # 80GB blank disk
  installerIso = "/path/to/windows-11.iso";          # Mount installer
  bootOrder = "cd";                                  # Boot from CD-ROM first
  memory = 4096;
  smp = 4;
  vncPort = 2;
  uefi = true;                                       # Windows needs UEFI
};
```

### 3. Cloud-init Linux VM
```nix
virtualisation.qemu.manager.services."ubuntu-cloudinit" = {
  enable = true;
  baseImage = null;                          # Blank disk
  diskSizeGB = 20;
  installerIso = "/path/to/ubuntu-22.04.iso";
  memory = 2048;
  vncPort = 3;
  
  cloudInit = {
    enable = true;
    userData = ''
      #cloud-config
      users:
        - name: admin
          sudo: ALL=(ALL) NOPASSWD:ALL
          ssh_authorized_keys:
            - ssh-rsa AAAAB3NzaC1yc2E... your-key-here
      packages:
        - htop
        - curl
      runcmd:
        - systemctl enable ssh
    '';
    metaData = ''
      instance-id: ubuntu-cloudinit-001
      local-hostname: ubuntu-cloudinit
    '';
    networkConfig = ''
      version: 2
      ethernets:
        enp1s0:
          dhcp4: true
    '';
  };
};
```

### 4. Ubuntu Server with Cloud-init (Using Base Image)
```nix
virtualisation.qemu.manager = {
  images."ubuntu-cloud" = {
    enable = true;
    source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img";
    sourceSha256 = "...";
    sourceFormat = "qcow2";
    resizeGB = 20;
  };

  services."ubuntu-cloud-server" = {
    enable = true;
    baseImage = "ubuntu-cloud";
    memory = 2048;
    vncPort = 4;
    
    cloudInit = {
      enable = true;
      userData = ''
        #cloud-config
        users:
          - name: ubuntu
            sudo: ALL=(ALL) NOPASSWD:ALL
            ssh_authorized_keys:
              - ssh-rsa AAAAB3NzaC1yc2E... your-key-here
        package_update: true
        package_upgrade: true
        packages:
          - docker.io
          - nginx
      '';
    };
  };
};
```

## Directory Structure

- **Base images**: `/var/lib/vm/base-images/` (e.g., `ubuntu-22.04.qcow2`)
- **VM disks**: `/var/lib/vm/images/` (e.g., `ubuntu-server-ubuntu-22.04.qcow2`)
- **Cloud-init ISOs**: `/var/lib/vm/images/` (e.g., `ubuntu-server-cloud-init.iso`)

## Boot Order Options

- `"cd"`: Boot from CD-ROM first, then disk (for installation)
- `"dc"`: Boot from disk first, then CD-ROM (after installation)
- `"c"`: Boot from CD-ROM only
- `"d"`: Boot from disk only

## Cloud-init File Types

- **user-data**: Main configuration (users, packages, commands)
- **meta-data**: Instance metadata (hostname, instance-id)
- **network-config**: Network configuration (static IP, etc.)

## Workflow

### For Windows/Other OS Installation:
1. Set `baseImage = null` and provide `installerIso`
2. Set `bootOrder = "cd"` to boot from ISO first
3. Install OS via VNC
4. After installation, change `bootOrder = "dc"` and remove `installerIso`
5. Rebuild to boot from disk

### For Linux with Cloud-init:
1. Use cloud images with `baseImage` OR blank disk with installer ISO
2. Configure `cloudInit` section with your preferences
3. VM will auto-configure on first boot

## Management Commands

```bash
# Start/stop VMs
sudo systemctl start qemu-vm-name
sudo systemctl stop qemu-vm-name

# View console
console-vm-name  # (automatically created alias)

# View logs
journalctl -u qemu-vm-name -f
```

## TODO: 
- run as own user instead of root
- make vm overlay dir an option
- cleanup, option descriptions and examples
