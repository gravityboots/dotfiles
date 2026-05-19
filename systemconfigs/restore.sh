#!/bin/bash
set -e

echo "==> Restoring system configs (requires sudo)"

sudo cp ~/systemconfigs/etc/pacman.d/hooks/*.hook /etc/pacman.d/hooks/
sudo cp ~/systemconfigs/boot/efi/EFI/refind/refind.conf /boot/efi/EFI/refind/

if [ -d ~/systemconfigs/boot/efi/EFI/refind/rEFInd-minimal ]; then
    sudo cp -r ~/systemconfigs/boot/efi/EFI/refind/rEFInd-minimal /boot/efi/EFI/refind/
fi
if [ -d ~/systemconfigs/boot/efi/EFI/refind/refind-black ]; then
    sudo cp -r ~/systemconfigs/boot/efi/EFI/refind/refind-black /boot/efi/EFI/refind/
fi

if [ -f ~/systemconfigs/etc/sudoers.d/mute-led ]; then
    sudo cp ~/systemconfigs/etc/sudoers.d/mute-led /etc/sudoers.d/
    sudo chmod 440 /etc/sudoers.d/mute-led
fi

echo "==> Done. Manual follow-ups required:"
echo "  - sbctl: regenerate or import keys, sign EFI binaries"
echo "  - Enroll keys in BIOS, enable secure boot"
echo "  - Copy kernel files to ESP (or wait for next kernel update for the hook to fire)"
