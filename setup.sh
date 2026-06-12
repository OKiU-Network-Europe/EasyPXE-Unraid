#!/bin/sh
# One-time setup: download the iPXE first-stage bootloaders into tftp/.
# Run on the Unraid server:  cd /mnt/user/appdata/pxe-server && sh setup.sh
set -e

cd "$(dirname "$0")"
mkdir -p tftp http/boot

echo "Downloading iPXE bootloaders from boot.ipxe.org ..."
# Note: EFI binaries live under the x86_64-efi/ subdirectory on boot.ipxe.org
curl -fL -o tftp/undionly.kpxe https://boot.ipxe.org/undionly.kpxe              # Legacy BIOS
curl -fL -o tftp/ipxe.efi      https://boot.ipxe.org/x86_64-efi/ipxe.efi        # UEFI x86-64
curl -fL -o tftp/snponly.efi   https://boot.ipxe.org/x86_64-efi/snponly.efi     # UEFI fallback (uses firmware NIC driver)

# Recent iPXE builds automatically fetch autoexec.ipxe from the TFTP server
# they were loaded from. Generating it here makes stage 2 (jump to the HTTP
# menu) independent of any DHCP filename games - the most robust path.
if [ -f .env ]; then
  . ./.env
  cat > tftp/autoexec.ipxe <<EOF
#!ipxe
chain http://${UNRAID_IP}:${HTTP_PORT}/boot.ipxe
EOF
  echo "Generated tftp/autoexec.ipxe -> http://${UNRAID_IP}:${HTTP_PORT}/boot.ipxe"
fi

echo
ls -lh tftp/
echo
echo "Done. Next steps:"
echo "  1. Edit .env (UNRAID_IP, SUBNET, HTTP_PORT)"
echo "  2. docker compose up -d"
echo "  3. PXE-boot a client (Secure Boot disabled)"
