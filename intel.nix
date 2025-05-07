{ config, lib, ... }:

let
  cfg = config.virtualisation.intel; 
in
{
  options.virtualisation.intel = {
    enable = lib.mkEnableOption "intel virtualisation";
  };

  config = lib.mkIf cfg.enable {
    boot = {
      kernelParams = [ "intel_iommu=on" ];
      initrd.kernelModules = [ "kvm_intel" ];
      extraModprobeConfig = ''
        options kvm_intel nested=1 
      '';
    };

    hardware.cpu.intel.updateMicrocode = true;
  };
}