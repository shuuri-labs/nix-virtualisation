{ lib, pkgs }:

rec {
  mkTapArgs = hostBridges: smp:
    let
      # Generate a deterministic MAC from an integer idx
      mkMac = idx:
        let
          # Simple hex conversion with padding
          hex = builtins.toString (idx + 1);  # Start from 1 to avoid 00:00:00
          # Ensure 6 digits by padding with zeros
          padded = "000000" + hex;
          # Take last 6 digits
          last6 = builtins.substring (builtins.stringLength padded - 6) 6 padded;
          # Split into octets
          octets = [
            (builtins.substring 0 2 last6)
            (builtins.substring 2 2 last6)
            (builtins.substring 4 2 last6)
          ];
          # Use different prefix for first interface to avoid bridge MAC conflicts
          prefix = if idx == 0 then ["52" "54" "01"] else ["52" "54" "00"];
        in
          builtins.concatStringsSep ":" (prefix ++ octets);
    in
      builtins.concatLists (builtins.genList (idx: [
        "-netdev" "tap,id=net${builtins.toString idx},br=${builtins.elemAt hostBridges idx},helper=/run/wrappers/bin/qemu-bridge-helper,vhost=on"
        "-device" "virtio-net-pci,netdev=net${builtins.toString idx},mac=${mkMac idx},mq=on,vectors=${builtins.toString (smp*2)},tx=bh"
      ]) (builtins.length hostBridges));

  mkPciPassthroughArgs = hosts:
    builtins.concatLists (builtins.map (h: [ "-device" "vfio-pci,host=${h.address}" ]) hosts);

  mkUsbPassthroughArgs = hosts:
    builtins.concatLists (builtins.map (h: [ "-device"
      "usb-host,vendorid=${h.vendorId},productid=${h.productId}" ]) hosts);

  mkExtraArgs = extra: builtins.concatLists (builtins.map (a: [ "-${a}" ]) extra);

  mkUefiArgs = name: enable: let
    code     = "${pkgs.OVMFFull.fd}/FV/OVMF_CODE.fd";
    varsFile = "/var/lib/libvirt/images/${name}-ovmf-vars.fd";
  in
    builtins.concatLists [
      (if enable then [ "-drive" "if=pflash,format=raw,readonly=on,file=${code}" ] else [])
      (if enable then [ "-drive" "if=pflash,format=raw,file=${varsFile}" ] else [])
    ];

  mkUefiPreStart = name: enable: 
    if enable then ''
      ${pkgs.coreutils}/bin/install -m0644 -o root -D \
        ${pkgs.OVMFFull.fd}/FV/OVMF_VARS.fd /var/lib/libvirt/images/${name}-ovmf-vars.fd
    '' else "";

  prettyArgs = args: builtins.concatStringsSep " \\\n  " args;
}
