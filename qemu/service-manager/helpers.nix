{ lib, pkgs }:

rec {
  mkTapArgs = hostBridges: smp:
    let
      # Generate a deterministic MAC from an integer idx
      mkMac = idx:
        let
          # Simple hex conversion using string manipulation
          hex = builtins.toString idx;
          # Pad with zeros to ensure 6 characters
          padded = builtins.substring 0 6 (hex + "000000");
          # Split into octets
          octets = [
            (builtins.substring 0 2 padded)
            (builtins.substring 2 2 padded)
            (builtins.substring 4 2 padded)
          ];
        in
          builtins.concatStringsSep ":" (["52" "54" "00"] ++ octets);
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
