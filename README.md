# nix-virtualisation

A declarative NixOS module for managing QEMU virtual machines. Define your entire VM infrastructure as code with support for base images, cloud-init provisioning, and hardware passthrough.

## Features

- **Declarative VM Management** - Define VMs entirely in Nix configuration with automatic systemd service generation
- **Base Image Support** - Automatically download, cache, and convert cloud images (Ubuntu, etc.)
- **Blank Disk VMs** - Create VMs from scratch with installer ISOs for Windows or other operating systems
- **Cloud-init Integration** - Automatic Linux VM provisioning with user-data, metadata, and network configuration
- **Hardware Passthrough** - PCI device passthrough with automatic VFIO binding and USB device passthrough
- **Network Management** - Host bridge support, automatic TAP interface creation, and MAC address generation
- **UEFI Support** - OVMF firmware for Windows and modern OS installations
- **VNC Access** - Automatic VNC configuration for VM console access

## Installation

Add the flake to your NixOS configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-virtualisation.url = "github:shuuri-labs/nix-virtualisation/version-2";
  };

  outputs = { self, nixpkgs, nix-virtualisation, ... }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-virtualisation.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

## Quick Start

### Enable Base Virtualization

```nix
{
  virtualisation.base.enable = true;

  # For Intel CPUs (optional, enables KVM optimizations)
  virtualisation.intel.enable = true;

  # For hardware passthrough (optional)
  virtualisation.bareMetal.enable = true;
}
```

### Create a VM with a Cloud Image

```nix
virtualisation.qemu.manager = {
  images."ubuntu-22.04" = {
    enable = true;
    source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img";
    sourceSha256 = "sha256-...";
    sourceFormat = "qcow2";
    resizeGB = 20;
  };

  services."ubuntu-server" = {
    enable = true;
    baseImage = "ubuntu-22.04";
    memory = 2048;
    smp = 2;
    vncPort = 1;
    hostBridges = [ "br0" ];

    cloudInit = {
      enable = true;
      userData = ''
        #cloud-config
        users:
          - name: admin
            sudo: ALL=(ALL) NOPASSWD:ALL
            ssh_authorized_keys:
              - ssh-rsa AAAAB3... your-key
        packages:
          - htop
          - curl
      '';
    };
  };
};
```

### Create a Windows VM

```nix
virtualisation.qemu.manager.services."windows-11" = {
  enable = true;
  baseImage = null;                        # No base image (blank disk)
  diskSizeGB = 80;
  installerIso = "/path/to/windows-11.iso";
  bootOrder = "cd";                        # Boot from CD-ROM first
  memory = 8192;
  smp = 4;
  vncPort = 2;
  uefi = true;                             # Windows requires UEFI
};
```

### Hardware Passthrough

```nix
virtualisation.qemu.manager.services."gaming-vm" = {
  enable = true;
  baseImage = "windows-base";
  memory = 16384;
  smp = 8;
  vncPort = 3;
  uefi = true;

  # PCI passthrough (e.g., GPU)
  pciHost = [
    { address = "0000:01:00.0"; }  # GPU
    { address = "0000:01:00.1"; }  # GPU Audio
  ];

  # USB passthrough
  usbHost = [
    { vendorId = "046d"; productId = "c52b"; }  # Logitech receiver
  ];
};
```

## Configuration Options

### Global Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `virtualisation.base.enable` | bool | `false` | Enable base virtualization (libvirtd, QEMU packages) |
| `virtualisation.intel.enable` | bool | `false` | Enable Intel-specific KVM features |
| `virtualisation.bareMetal.enable` | bool | `false` | Enable IOMMU/VFIO for device passthrough |
| `virtualisation.qemu.manager.imageDirectory` | path | `/var/lib/vm/images` | Directory for VM disk images |
| `virtualisation.qemu.manager.baseImageDirectory` | path | `/var/lib/vm/images/base` | Directory for cached base images |

### Image Options

| Option | Type | Description |
|--------|------|-------------|
| `enable` | bool | Enable this base image |
| `source` | string | URL to download the image from |
| `sourceSha256` | string | SHA256 hash for verification |
| `sourceFormat` | enum | Source format: `raw`, `vmdk`, `vdi`, `vhdx`, `qcow`, `qcow2` |
| `compression` | enum | Compression type: `none`, `zip`, `gz`, `bz2`, `xz` |
| `resizeGB` | int | Resize the image to this size in GB |

### Service (VM) Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable this VM |
| `baseImage` | string/null | `null` | Name of base image to use (null for blank disk) |
| `diskSizeGB` | int | `20` | Disk size in GB |
| `memory` | int | `1024` | RAM in MB |
| `smp` | int | `1` | Number of CPU cores |
| `vncPort` | int | `0` | VNC display number (access via `5900 + vncPort`) |
| `uefi` | bool | `false` | Enable UEFI boot |
| `bootOrder` | string | `"dc"` | Boot order (`cd`, `dc`, `c`, `d`) |
| `installerIso` | path/null | `null` | Path to installer ISO |
| `hostBridges` | list | `[]` | Host bridges for networking |
| `pciHost` | list | `[]` | PCI devices to passthrough |
| `usbHost` | list | `[]` | USB devices to passthrough |
| `cloudInit` | submodule | - | Cloud-init configuration |

### Cloud-init Options

| Option | Type | Description |
|--------|------|-------------|
| `enable` | bool | Enable cloud-init ISO generation |
| `userData` | string | Cloud-config user data |
| `metaData` | string | Instance metadata |
| `networkConfig` | string | Network configuration (Netplan v2 format) |

## Directory Structure

```
/var/lib/vm/
├── images/
│   ├── base/                    # Cached base images
│   │   └── ubuntu-22.04.qcow2
│   ├── ubuntu-server.qcow2      # VM disk images
│   └── ubuntu-server-cloud-init.iso
```

## Management Commands

```bash
# Start/stop VMs
sudo systemctl start qemu-ubuntu-server
sudo systemctl stop qemu-ubuntu-server

# View VM status
sudo systemctl status qemu-ubuntu-server

# Access VM console (via serial)
console-ubuntu-server    # Auto-generated alias

# View VM logs
journalctl -u qemu-ubuntu-server -f

# Connect via VNC
vncviewer localhost:5901  # Port = 5900 + vncPort
```

## Module Structure

```
nix-virtualisation/
├── flake.nix              # Flake configuration
├── default.nix            # Main module entry point
├── base.nix               # Base virtualization setup
├── bare-metal.nix         # IOMMU/VFIO configuration
├── intel.nix              # Intel KVM settings
└── qemu/
    ├── default.nix        # QEMU module aggregator
    ├── options.nix        # Configuration options
    ├── lib.nix            # Type definitions (exported)
    ├── README.md          # Detailed usage examples
    ├── image-manager/     # Image download/conversion
    └── service-manager/   # VM service generation
```

## Using the Type Library

The module exports type definitions for external use:

```nix
{
  inputs.nix-virtualisation.url = "github:your-username/nix-virtualisation";
}

# Access types via:
# nix-virtualisation.lib.image
# nix-virtualisation.lib.service
# nix-virtualisation.lib.cloudInit
# etc.
```

## Requirements

- NixOS (tested on nixos-unstable)
- Intel or AMD CPU with virtualization support (VT-x/AMD-V)
- For passthrough: IOMMU support (VT-d/AMD-Vi)

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.
