{ config, lib, pkgs, ... }:

let
  cfg                = config.virtualisation.qemu.manager;
  imageDirectory     = cfg.imageDirectory;
  baseImageDirectory = cfg.baseImageDirectory;
  helpers            = import ./helpers.nix { inherit lib pkgs; };

  hostBridgeNames = lib.unique (lib.flatten (lib.mapAttrsToList (_: v: v.hostBridges) cfg.services));
  vncPorts        = map (n: 5900 + n) (lib.collect lib.isInt (lib.mapAttrsToList (_: v: v.vncPort) cfg.services));
  pciAddresses    = lib.unique (lib.flatten (lib.mapAttrsToList (_: v:
                     lib.map (h: h.address) v.pciHosts) cfg.services));
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
      # Determine if we're using a base image or creating a blank disk
      useBaseImage = v.baseImage != null;
      base = if useBaseImage then "${baseImageDirectory}/${v.baseImage}.qcow2" else null;
      format = "qcow2";

      preScript = ''
        #!/usr/bin/env bash
        set -euo pipefail

        # 1) UEFI setup if requested
        ${helpers.mkUefiPreStart name v.uefi}

        # 2) Handle disk creation based on mode
        ${if useBaseImage then ''
          # Using base image - copy it for this VM
          base='${base}'
          format='${format}'
          vmImage='${imageDirectory}/${name}-${v.baseImage}.qcow2'
          
          if [ ! -f "$vmImage" ] || [ "$base" -nt "$vmImage" ]; then
            mkdir -p '${imageDirectory}'
            echo "Copying base image ${v.baseImage} for VM ${name}..."
            cp "$base" "$vmImage"
          fi
        '' else ''
          # Creating blank disk
          vmImage='${imageDirectory}/${name}.qcow2'
          
          if [ ! -f "$vmImage" ]; then
            mkdir -p '${imageDirectory}'
            echo "Creating blank disk for VM ${name} (${toString v.diskSizeGB}GB)..."
            ${pkgs.qemu}/bin/qemu-img create -f qcow2 "$vmImage" ${toString v.diskSizeGB}G
          fi
        ''}

        ${lib.optionalString v.cloudInit.enable ''
          # 3) Generate cloud-init ISO if enabled
          cloudInitIso='${imageDirectory}/${name}-cloud-init.iso'
          cloudInitDir=$(mktemp -d)
          trap "rm -rf $cloudInitDir" EXIT
          
          ${lib.optionalString (v.cloudInit.userData != null) ''
            echo '${v.cloudInit.userData}' > "$cloudInitDir/user-data"
          ''}
          ${lib.optionalString (v.cloudInit.metaData != null) ''
            echo '${v.cloudInit.metaData}' > "$cloudInitDir/meta-data"
          ''}
          ${lib.optionalString (v.cloudInit.networkConfig != null) ''
            echo '${v.cloudInit.networkConfig}' > "$cloudInitDir/network-config"
          ''}
          
          # Create cloud-init ISO if it doesn't exist or if config changed
          if [ ! -f "$cloudInitIso" ]; then
            echo "Creating cloud-init ISO for VM ${name}..."
            ${pkgs.genisoimage}/bin/genisoimage \
              -output "$cloudInitIso" \
              -volid cidata \
              -joliet \
              -rock \
              "$cloudInitDir"
          fi
        ''}
      '';

    in {
      description       = "QEMU VM: ${name}";
      wantedBy          = [ "multi-user.target" ];
      after             = lib.optionals (v.pciHosts != []) [ "vfio-pci-bind.service" ]
                            ++ lib.optionals useBaseImage [ "prepare-qemu-image-${v.baseImage}.service" ];
      requires          = lib.optionals (v.pciHosts != []) [ "vfio-pci-bind.service" ]
                            ++ lib.optionals useBaseImage [ "prepare-qemu-image-${v.baseImage}.service" ];
      path              = [ pkgs.qemu pkgs.socat pkgs.genisoimage ];
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
                   "-drive"  "file=${imageDirectory}/${name}-${if useBaseImage then v.baseImage else ""}.qcow2,if=none,id=drive0,format=qcow2"
                   "-device" "scsi-hd,drive=drive0"
                 ] else [
                   "-drive" "file=${imageDirectory}/${name}-${if useBaseImage then v.baseImage else ""}.qcow2,if=virtio,format=qcow2"
                 ])

              # core machine options
              ++ [
                   "-enable-kvm" "-machine" "q35" "-cpu" v.cpuType
                   "-m" (toString v.memory) "-smp" (toString v.smp)
                   "-device" "usb-ehci" "-device" "usb-tablet"
                   "-display" "vnc=:${toString v.vncPort}"
                   "-serial" "unix:/tmp/${name}-console.sock,server,nowait"
                   "-boot" "order=${v.bootOrder}"
                 ]
              
              # installer ISO mounting
              ++ lib.optionals (v.installerIso != null) [
                   "-drive" "file=${v.installerIso},if=ide,index=0,media=cdrom,readonly=on"
                 ]
              
              # cloud-init ISO mounting
              ++ lib.optionals v.cloudInit.enable [
                   "-drive" "file=${imageDirectory}/${name}-cloud-init.iso,if=ide,index=1,media=cdrom,readonly=on"
                 ]

              # bridges, PCI & USB passthrough, extra args
              ++ helpers.mkTapArgs            v.hostBridges cfg.hostName name v.smp
              # ++ helpers.mkUserNetArgs        name v.portForwards
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