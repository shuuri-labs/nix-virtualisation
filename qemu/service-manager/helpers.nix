{ lib, pkgs }:

rec {
  # Generate a simple MAC by appending a padded number to the base MAC
  genMac = hostName: vmName: idx: let
    hostNameHash = builtins.hashString "md5" hostName;
    vmNameHash = builtins.hashString "md5" vmName;
    # Generate a simple MAC by appending a padded number to the base MAC
    secondOctet = builtins.substring 0 2 hostNameHash;
    thirdOctet = builtins.substring 2 2 hostNameHash;

    fourthOctet = builtins.substring 0 2 vmNameHash;
    fifthOctet = builtins.substring 2 2 vmNameHash;

    lastOctet = if idx < 10 then "0${builtins.toString idx}" else builtins.toString idx;
  in "02:${secondOctet}:${thirdOctet}:${fourthOctet}:${fifthOctet}:${lastOctet}";

  mkTapArgs = hostBridges: hostName: vmName: smp:
    builtins.concatLists (builtins.genList (idx: [
      "-netdev" "tap,id=${vmName}-net${builtins.toString idx},br=${builtins.elemAt hostBridges idx},helper=/run/wrappers/bin/qemu-bridge-helper,vhost=on"
      "-device" "virtio-net-pci,netdev=${vmName}-net${builtins.toString idx},mac=${genMac hostName vmName idx},mq=on,vectors=${builtins.toString (smp*2)},tx=bh"
    ]) (builtins.length hostBridges));

  mkPciPassthroughArgs = hosts:
    builtins.concatLists (builtins.map (h: [ "-device" "vfio-pci,host=${h.address}" ]) hosts);

  # mkUserNetArgs = vmName: portForwards:
  #   if builtins.length portForwards > 0 then
  #     let
  #       hostfwdList = builtins.map (portForward: 
  #         "tcp::${builtins.toString portForward.hostPort}-:${builtins.toString portForward.vmPort}"
  #       ) portForwards;
  #       hostfwdStr = builtins.concatStringsSep ",hostfwd=" hostfwdList;
  #     in [
  #       "-netdev" "user,id=${vmName}-user,hostfwd=${hostfwdStr}"
  #       "-device" "virtio-net-pci,netdev=${vmName}-user"
  #     ]
  #   else [];

  mkUsbPassthroughArgs = hosts:
    if builtins.length hosts > 0 then
      [ "-usb" "-device" "qemu-xhci,id=xhci" ] ++
      (builtins.map (h: "-device usb-host,bus=xhci.0,vendorid=${h.vendorId},productid=${h.productId}") hosts)
    else [];

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
