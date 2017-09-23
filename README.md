# usb-efi-boot-builder

Given:

- Kernel sources at `/usr/src/linux`, with a config as `.config`
- A GPG symmetric key at `/boot/overlay/key.gpg`
- A VFAT volume mounted at `/usbboot`
- `genkernel` installed (a gentoo thing)
- Common tools like coreutils and util-linux

Running `./build.sh` will yield:

- A built kernel+modules and initramfs image, with boot necessities copied to the USB stick
- GPG encryption of the boot image
- All as an EFI boot image that can be directly booted without a bootloader
- Backups of the build script itself (so you can rebuild from the USB stick) and the GPG key

Clearly, your GPG symmetric key should be protected with a passphrase. The initramfs knows how to deal with that.

## License

Copyright 2017 Ben Chociej. Available to all under the Apache-2.0 license. See `LICENSE`.
