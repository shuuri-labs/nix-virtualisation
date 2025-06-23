{ config, lib, pkgs, ... }:

let
  cfg             = config.virtualisation.qemu.manager;
  helpers         = import ./helpers.nix { inherit lib pkgs; };
  hostBridgeNames = lib.unique (lib.flatten (lib.mapAttrsToList (_: v: v.hostBridges) cfg.services));
  vncPorts        = map (n: 5900 + n) (lib.collect lib.isInt (lib.mapAttrsToList (_: v: v.vncPort) cfg.services));
  # Get unique PCI addresses for device-specific binding
  pciAddresses    = lib.unique (lib.flatten (lib.mapAttrsToList (_: v:
                     lib.map (h: h.address) v.pciHosts) cfg.services));
  imageDirectory  = "/var/lib/vm/images";
in {
  config = lib.mkIf (cfg.services != {}) {
    virtualisation.libvirtd.allowedBridges =  hostBridgeNames;

    networking.firewall.extraCommands = lib.mkAfter ''
      ${lib.concatStringsSep "\n"
        (map (br: ''
          iptables -A FORWARD -i ${br} -j ACCEPT
          iptables -A FORWARD -o ${br} -j ACCEPT
        '') hostBridgeNames)}
    ''; # add firewall rule to block traffic from VMs to non-router mac addresses (TODO)

    networking.firewall.allowedTCPPorts = vncPorts;

    # ensure overlay dir exists
    systemd.tmpfiles.rules = [ "d ${imageDirectory} 0755 root root - -" ];

    environment.systemPackages = [ pkgs.socat ];

    systemd.services = lib.mapAttrs (name: v: lib.mkIf v.enable (
    let
      # precompute the backing-store image for this service
      base   = "${config.virtualisation.qemu.manager.builtImages.${v.baseImage}}/${v.baseImage}.qcow2";
      format = "qcow2";

      preScript = ''
        #!/usr/bin/env bash
        set -euo pipefail

        # 1) UEFI setup if requested
        ${helpers.mkUefiPreStart name v.uefi}

        # 2) Known backing-image path and format
        base='${base}'
        format='${format}'

        # 3) Extract the Nix store hash from the directory name
        baseDir=$(dirname "$base")
        storeHash=$(basename "$baseDir")

        # 4) Construct a hash-specific overlay filename
        realOverlay='${imageDirectory}/${name}-'"$storeHash"'.qcow2'

        # 5) Create that overlay only if it doesn't already exist
        if [ ! -f "$realOverlay" ]; then
          mkdir -p '${imageDirectory}'
          ${pkgs.qemu}/bin/qemu-img create \
            -f qcow2 \
            -F "$format" \
            -b "$base" \
            "$realOverlay"
        fi

        # 6) Atomically update a stable symlink for QEMU to use
        ln -sf "$(basename "$realOverlay")" '${imageDirectory}/${name}.qcow2'
      '';

    in {
      description     = "QEMU VM: ${name}";
      wantedBy        = [ "multi-user.target" ];
      after           = lib.optional (v.pciHosts != []) "vfio-pci-bind.service";
      requires        = lib.optional (v.pciHosts != []) "vfio-pci-bind.service";
      path            = [ pkgs.qemu pkgs.socat ];

      restartTriggers   = [
        config.virtualisation.qemu.manager.builtImages.${v.baseImage}.drvPath
      ];
      restartIfChanged  = true;

      serviceConfig = {
        Type           = "simple";
        Restart        = v.restart;
        ReadWritePaths = [ imageDirectory ];
        ExecStartPre   = pkgs.writeShellScript "qemu-${name}-pre.sh" preScript;
        ExecStart      = ''
          ${pkgs.qemu}/bin/qemu-system-x86_64 \
            ${helpers.prettyArgs (
              # pflash drives if UEFI
              helpers.mkUefiArgs name v.uefi

              # root disk: virtio vs SCSI
              ++ (if v.rootScsi then [
                   "-device" "virtio-scsi-pci"
                   "-drive"  "file=${imageDirectory}/${name}.qcow2,if=none,id=drive0,format=qcow2"
                   "-device" "scsi-hd,drive=drive0"
                 ] else [
                   "-drive" "file=${imageDirectory}/${name}.qcow2,if=virtio,format=qcow2"
                 ])

              # core machine options
              ++ [
                   "-enable-kvm" "-machine" "q35" "-cpu" "host"
                   "-m" (toString v.memory) "-smp" (toString v.smp)
                   "-device" "usb-ehci" "-device" "usb-tablet"
                   "-display" "vnc=:${toString v.vncPort}"
                   "-serial" "unix:/tmp/${name}-console.sock,server,nowait"
                 ]

              # bridges, PCI & USB passthrough, extra args
              ++ helpers.mkTapArgs            v.hostBridges cfg.hostName name v.smp
              ++ helpers.mkUserNetArgs        name v.hostfwdRules
              ++ helpers.mkPciPassthroughArgs v.pciHosts
              ++ helpers.mkUsbPassthroughArgs v.usbHosts
              ++ helpers.mkExtraArgs          v.extraArgs
            )}
        '';
        # Critical systemd settings for graceful shutdown
        ExecStop   = "${pkgs.coreutils}/bin/kill -s SIGRTMIN+3 $MAINPID";
        KillSignal = "SIGRTMIN+3";
        TimeoutStopSec = "10min";
        KillMode   = "mixed";
      };
    }
    )) cfg.services
    # Add the VFIO binding service
    // lib.optionalAttrs (pciAddresses != []) {
      vfio-pci-bind = {
        description = "Bind specific PCI devices to VFIO";
        wantedBy = [ "multi-user.target" ];
        before = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "vfio-pci-bind" ''
            # Enable VFIO modules
            ${pkgs.kmod}/bin/modprobe vfio-pci
            
            ${lib.concatStringsSep "\n" (map (addr: ''
              # Bind ${addr} to VFIO
              echo "0000:${addr}" > /sys/bus/pci/devices/0000:${addr}/driver/unbind 2>/dev/null || true
              echo "vfio-pci" > /sys/bus/pci/devices/0000:${addr}/driver_override
              echo "0000:${addr}" > /sys/bus/pci/drivers/vfio-pci/bind
            '') pciAddresses)}
          '';
          ExecStop = pkgs.writeShellScript "vfio-pci-unbind" ''
            ${lib.concatStringsSep "\n" (map (addr: ''
              # Unbind ${addr} from VFIO
              echo "0000:${addr}" > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null || true
              echo > /sys/bus/pci/devices/0000:${addr}/driver_override
            '') pciAddresses)}
          '';
        };
      };
    };

    # console aliases
    environment.shellAliases = lib.mapAttrs' (n: _: {
      name  = "console-${n}";
      value = "sudo socat UNIX-CONNECT:/tmp/${n}-console.sock stdio";
    }) cfg.services;
  };
}