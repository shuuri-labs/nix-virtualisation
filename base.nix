{ config, lib, pkgs, ... }:

let
  cfg = config.virtualisation; 
in
{
  options.virtualisation = {
    base.enable = lib.mkEnableOption "virtualisation";

    mainUser = lib.mkOption {
      type = lib.types.str;
      description = "Main user for virtualisation";
      default = "ashley";
    };
  };

  config = lib.mkIf cfg.base.enable {
    users.users.${cfg.mainUser}.extraGroups = [ "libvirtd" ];
    
    environment.systemPackages = with pkgs; [
      qemu
      libvirt
      spice-gtk
      socat
    ];

    boot.kernelModules = [ "vhost_net" ];

    virtualisation.libvirtd = {
      enable = true;
      allowedBridges = [ "virbr0" ];
    };
  };
}
