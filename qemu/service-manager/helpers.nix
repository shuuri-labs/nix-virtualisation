{ lib, pkgs }:

rec {
  mkTapArgs = hostBridges: smp:
    let
      # Generate a deterministic MAC from an integer idx
      mkMac = idx:
        let
          hx    = lib.formatInt 16 idx;
          hx6   = lib.padLeft 6 "0" hx;
          octets = lib.map (i: lib.substring (2 * i) (2 * i + 2) hx6) (lib.range 0 2);
        in
          lib.concatStringsSep ":" (["52" "54" "00"] ++ octets);
    in
      lib.flatten (lib.imap0 (idx: bridge: [
        "-netdev" "tap,id=net${toString idx},br=${bridge},helper=/run/wrappers/bin/qemu-bridge-helper,vhost=on"
        "-device" "virtio-net-pci,netdev=net${toString idx},mac=${mkMac idx},mq=on,vectors=${toString (smp*2)},tx=bh"
      ]) hostBridges);

  mkPciPassthroughArgs = hosts:
    lib.concatMap (h: [ "-device" "vfio-pci,host=${h.address}" ]) hosts;

  mkUsbPassthroughArgs = hosts:
    lib.concatMap (h: [ "-device"
      "usb-host,vendorid=${h.vendorId},productid=${h.productId}" ]) hosts;

  mkExtraArgs = extra: lib.concatMap (a: [ "-${a}" ]) extra;

  mkUefiArgs = name: enable: let
    code     = "${pkgs.OVMFFull.fd}/FV/OVMF_CODE.fd";
    varsFile = "/var/lib/libvirt/images/${name}-ovmf-vars.fd";
  in
    lib.optional enable "-drive if=pflash,format=raw,readonly=on,file=${code}"
  ++ lib.optional enable "-drive if=pflash,format=raw,file=${varsFile}";

  mkUefiPreStart = name: enable: 
    if enable then ''
      ${pkgs.coreutils}/bin/install -m0644 -o root -D \
        ${pkgs.OVMFFull.fd}/FV/OVMF_VARS.fd /var/lib/libvirt/images/${name}-ovmf-vars.fd
    '' else "";

  prettyArgs = args: lib.concatStringsSep " \\\n  " args;
}
