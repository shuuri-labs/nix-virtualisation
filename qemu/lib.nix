{ lib }:

let
  # Define basic types first
  image = lib.types.submodule {
    options = {
      enable = lib.mkEnableOption "Build and convert this QEMU image";

      source = lib.mkOption {
        type        = lib.types.nullOr (lib.types.either lib.types.str lib.types.package);
        default     = null;
        description = ''
          Remote URL or local path to fetch the image from.
          If local path, prefix with: file://
        '';
      };

      sourceSha256 = lib.mkOption {
        type        = lib.types.nullOr lib.types.str;
        default     = null;
        description = '' 
          Required if `source` is a remote URL.  
          If source is a local path, prefix with: file://
          You can get the sha256 by running `nix-prefetch-url <url>`
        '';
      };

      sourceFormat = lib.mkOption {
        type        = lib.types.enum [ "raw" "vmdk" "vdi" "vhdx" "qcow" "qcow2" ];
        default     = "raw";
        description = "Format of the source image.";
      };

      compressedFormat = lib.mkOption {
        type        = lib.types.nullOr (lib.types.enum [ "zip" "gz" "bz2" "xz" ]);
        default     = null;
        description = "Decompression type, if the source is an archive.";
      };

      resizeGB = lib.mkOption {
        type        = lib.types.nullOr lib.types.ints.positive;
        default     = null;
        description = "If set, resize the resulting qcow2 to this size in GiB.";
      };
    };
  };

  usbHost = lib.types.submodule {
    options = {
      vendorId  = lib.mkOption { type = lib.types.str; };
      productId = lib.mkOption { type = lib.types.str; };
    };
  };

  pciHost = lib.types.submodule {
      options = {
        address = lib.mkOption { type = lib.types.str; };
    };
  };

  portForward = lib.types.submodule {
    options = {
      hostPort = lib.mkOption { type = lib.types.ints.positive; };
      vmPort   = lib.mkOption { type = lib.types.ints.positive; };
    };
  };

  tap = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      macAddress = lib.mkOption { type = lib.types.str; };
    };
  };

  cloudInit = lib.types.submodule {
    options = {
      enable = lib.mkEnableOption "cloud-init configuration";
      
      userData = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Cloud-init user-data content or path to file.";
      };
      
      metaData = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Cloud-init meta-data content or path to file.";
      };
      
      networkConfig = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Cloud-init network-config content or path to file.";
      };
    };
  };

  # Define service type that references the above types
  service = lib.types.submodule {
    options = {
      enable       = lib.mkEnableOption "QEMU virtual machine";
      baseImage    = lib.mkOption { 
        type = lib.types.nullOr lib.types.str; 
        default = null;
        description = "Base image to use. If null, creates a blank disk.";
      };
      rootScsi     = lib.mkOption { type = lib.types.bool; default = false; };
      uefi         = lib.mkOption { type = lib.types.bool; default = false; };
      cpuType      = lib.mkOption { type = lib.types.str;  default = "host"; };
      memory       = lib.mkOption { type = lib.types.ints.positive; default = 512; };
      smp          = lib.mkOption { type = lib.types.ints.positive; default = 2; };
      hostBridges  = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
      portForwards = lib.mkOption { type = lib.types.listOf portForward; default = []; };
      pciHosts     = lib.mkOption { type = lib.types.listOf pciHost; default = []; };
      usbHosts     = lib.mkOption { type = lib.types.listOf usbHost; default = []; };
      vncPort      = lib.mkOption { type = lib.types.ints.between 0 99; };
      extraArgs    = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
      restart      = lib.mkOption { type = lib.types.str; default = "always"; };
      
      # Blank disk configuration
      diskSizeGB   = lib.mkOption { 
        type = lib.types.ints.positive; 
        default = 20;
        description = "Size of the disk in GB when creating blank disks.";
      };
      
      # Installation support
      installerIso = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to installer ISO to mount as CD-ROM.";
      };
      
      bootOrder = lib.mkOption {
        type = lib.types.str;
        default = "cd";
        description = "Boot order: 'cd' for CD-ROM first, 'dc' for disk first.";
      };
      
      # Cloud-init support  
      cloudInit = lib.mkOption {
        type = cloudInit;
        default = {};
      };
    };
  };
in
{
  types = {
    inherit image usbHost pciHost portForward tap cloudInit service;
  };
} 