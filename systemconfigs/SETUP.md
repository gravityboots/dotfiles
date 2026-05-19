# System Setup Recovery Notes

## Order of operations on fresh CachyOS install

1. Boot fresh CachyOS install
2. Get terminal access, install yadm + git: `sudo pacman -S yadm git`
3. `yadm clone https://github.com/gravityboots/dotfiles.git`
4. Approve bootstrap when prompted (installs packages, copies system configs)
5. rEFInd setup:
   - ESP is at /boot/efi (CachyOS split layout)
   - Kernel lives at /boot/vmlinuz-linux-cachyos on btrfs
   - Hook /etc/pacman.d/hooks/95-cachyos-esp-copy.hook copies kernel to /boot/efi/EFI/cachyos/ on every update
   - First time: run `sudo /boot/efi/EFI/cachyos/setup-kernel.sh` or trigger pacman to fire the hook
6. Secure Boot:
   - `sudo pacman -S sbctl`
   - `sudo sbctl create-keys` (only if no keys exist yet)
   - `sudo sbctl enroll-keys -m` (enrolls Microsoft keys too)
   - `sudo sbctl sign -s <file>` for each .efi binary in /boot/efi
   - Reboot to BIOS, enable secure boot
7. Reboot, pick CachyOS from rEFInd

## Critical gotchas
- netbird: keep service disabled or it hijacks DNS
- spotify: launch via ~/.local/share/applications/spotify.desktop for correct scaling
- noctalia: do NOT populate bar.screenOverrides in settings.json — GUI edits get masked

## Mounting Windows partitions

Your Windows install is on /dev/nvme1n1p3 (NTFS). To auto-mount on boot:

1. Install ntfs-3g if not already:
   sudo pacman -S ntfs-3g

2. Identify the partition UUID:
   sudo blkid | grep -i ntfs

3. Create mount point:
   sudo mkdir -p /mnt/windows

4. Add to /etc/fstab (replace UUID with yours):
   UUID=<windows-uuid> /mnt/windows ntfs-3g defaults,uid=1000,gid=1000,umask=022,nofail,x-systemd.device-timeout=5 0 0

   - uid/gid=1000 makes the mount owned by your user
   - nofail prevents boot failure if Windows is disconnected
   - x-systemd.device-timeout=5 prevents long waits during boot if the partition is missing

5. Test before reboot:
   sudo mount -a
   ls /mnt/windows
   # should show your Windows C: contents

6. If mounting fails with "metadata kept in Windows cache, refused to mount":
   - This happens when Windows hibernated or didn't shut down cleanly
   - Boot into Windows, do Settings → System → Power → "Turn off fast startup"
   - Or do a full Windows shutdown (Shift+click Shutdown bypasses fast startup once)
   - Then retry mount

7. Optional: also mount the Windows ESP (/dev/nvme1n1p1) read-only for inspection.
   Don't write to it.

## Bluetooth and audio setup

### Audio basics (PipeWire on CachyOS)
PipeWire should work out of the box. Verify:
   systemctl --user status pipewire pipewire-pulse wireplumber
   pactl info | grep "Server Name"   # should say PipeWire
   wpctl status                       # lists all audio devices

If audio doesn't work after fresh install:
   systemctl --user enable --now pipewire pipewire-pulse wireplumber

### Bluetooth setup
1. Enable bluetooth service:
   sudo systemctl enable --now bluetooth

2. Bluetooth needs to be unblocked:
   rfkill list
   sudo rfkill unblock bluetooth

3. Pair a device:
   bluetoothctl
   > power on
   > agent on
   > scan on
   # wait for device MAC to appear
   > pair AA:BB:CC:DD:EE:FF
   > trust AA:BB:CC:DD:EE:FF
   > connect AA:BB:CC:DD:EE:FF
   > exit

   Or use noctalia's bluetooth panel in the bar.

### Common headphone issues

**Headphones connect but no audio:**
- Wrong profile (HSP/HFP vs A2DP). Run:
  wpctl status
  # find your headphone device, note the ID
  wpctl set-default <id>
- If profile is HSP/HFP (mono call quality), switch to A2DP:
  pactl list cards | grep -A 30 bluez
  pactl set-card-profile <card-name> a2dp-sink

**Media keys don't pause/skip from headphones (but volume works):**
- Install playerctl:
  sudo pacman -S playerctl
- Already configured in hyprland.conf with:
  bindl = , XF86AudioPlay, exec, playerctl play-pause
  bindl = , XF86AudioNext, exec, playerctl next
  bindl = , XF86AudioPrev, exec, playerctl previous

**Codec / sample rate issues (audio crackles or sounds wrong):**
Check the active codec:
   pactl list sinks | grep -i codec
For LDAC/aptX-HD headphones, may need:
   sudo pacman -S libldac

**Audio cuts out on first sound after silence:**
This is a known PipeWire idle-sleep issue. The custom config at:
   ~/.config/pipewire/pipewire.conf.d/99-custom.conf
should already handle this (tracked in repo).

### Mic mute LED on HP Victus
The script at /usr/local/bin/mute-toggle.sh keeps the keyboard mute LED in sync with PipeWire's mute state. Required setup:
- sudoers rule at /etc/sudoers.d/mute-led (in systemconfigs/)
- Hyprland bind:
  bindl = , XF86AudioMute, exec, /usr/local/bin/mute-toggle.sh
- The script itself needs to be restored to /usr/local/bin/ (consider adding it to systemconfigs/ if not already)

