{ config, lib, ... }:

let
  qemuLib = import ./lib.nix { inherit lib; };
  inherit (qemuLib.types) image usbHost pciHost portForward tap cloudInit service;
in
{
  options.virtualisation.qemu.manager = { 
    hostName = lib.mkOption { type = lib.types.str; default = config.networking.hostName; };

    imageDirectory = lib.mkOption {
      type        = lib.types.str;
      default     = "/var/lib/vm/images";
      description = "Directory to store the images for each VM.";
    };

    baseImageDirectory = lib.mkOption {
      type        = lib.types.str;
      default     = "/var/lib/vm/images/base";
      description = "Directory to store the base images.";
    };

    services = lib.mkOption {
      type = lib.types.attrsOf service;
      description = "Declarative configuration of QEMU virtual machines.";
      default = {};
      example = {
        "ubuntu-playground" = {
          enable = true;
          baseImage = "ubuntu-22.04";
          hostBridges = [ "br0" ];
          portForwards = [ { hostPort = 22; vmPort = 22; } ];
          pciHosts = [ { address = "0000:00:00.0"; } ];
          usbHosts = [ { vendorId = "046d"; productId = "082d"; } ];
          vncPort = 1;
          extraArgs = [ "nographic" ];
          restart = "always";
        };
      };
    };

    images = lib.mkOption {
      type = lib.types.attrsOf image;
      description = "Declarative download/unzip/convert of VM images to qcow2.";
      default = {};
      example = {
        "ubuntu-22.04" = {
          source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img";
          sourceSha256 = "0000000000000000000000000000000000000000000000000000000000000000";
        };
      };
    };
  };
}
