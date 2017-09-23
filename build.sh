#!/bin/bash

LEADER=">>"
THISSCRIPT=$(readlink -f $0)
TIMESTAMP=$(date +"%Y-%m-%d-%H%M.%S.%N")

echo
echo "Chociej's boot & usbboot builder"
echo

echo -n "$LEADER Checking /usbboot mount... "
if findmnt /usbboot >/dev/null 2>&1 ; then
	MNTOPTS=$(findmnt /usbboot | tail -n1 | awk '{ print $4 }')
	FSTYPE=$(findmnt /usbboot | tail -n1 | awk '{ print $3 }')

	if ! [[ ",$MNTOPTS," = *",rw,"* ]] ; then
		echo "error, not mounted rw"
		exit 1
	fi

	if ! [[ "$FSTYPE" = "vfat" ]] ; then
		echo "error, not vfat"
		exit 2
	fi
else
	echo "error, not mounted"
	exit 3
fi
echo ok

echo -n "$LEADER Checking for /boot/overlay/key.gpg... "
if ! [[ -f /boot/overlay/key.gpg ]] ; then
	echo "error, does not exist"
	exit 4
fi
echo ok

echo -n "$LEADER Checking for /usr/src/linux/.config... "
if ! [[ -f /usr/src/linux/.config ]] ; then
	echo "error, does not exist"
	exit 5
fi
echo ok

echo -n "$LEADER Checking for /usbboot/ files and directories... "
if ! [[ -d /usbboot/EFI/Boot/ ]] ; then
	if ! mkdir -p /usbboot/EFI/Boot/ ; then
		echo "error, /usbboot/EFT/Boot/ does not exist and could not be created"
		exit 6
	fi

	if [[ -f /usbboot/EFI/Boot/bootx64.efi ]] ; then
		if ! [[ -w /usbboot/EFI/Boot/bootx64.efi ]] ; then
			echo "error, /usbboot/EFI/Boot/bootx64.efi not writable"
			exit 7
		fi
	elif ! [[ -w /usbboot/EFI/Boot/ ]] ; then
		echo "error, /usbboot/EFI/Boot/ not writable"
		exit 8
	fi
fi
echo ok

echo -n "$LEADER Checking for genkernel... "
if ! [[ -x $(which genkernel) ]] ; then
	echo "error, no genkernel"
	exit 9
fi
echo ok

DIRTYKEY=0
if [[ -f /usbboot/key.gpg ]] ; then
	OVERLAYKEYSUM=$(sha512sum < /boot/overlay/key.gpg | awk '{ print $1 }')
	USBBOOTKEYSUM=$(sha512sum < /usbboot/key.gpg | awk '{ print $1 }')
	if [[ "x$OVERLAYKEYSUM" != "x$USBBOOTKEYSUM" ]] ; then 
		DIRTYKEY=1
		echo
		echo "$LEADER Backing up /usbboot/key.gpg... "
		cp -v /usbboot/key.gpg /usbboot/key.gpg-${TIMESTAMP}.backup
		if [[ $? -ne 0 ]] ; then
			echo "Error: backup key.gpg failed"
			exit 4
		fi
		echo
	fi
else
	DIRTYKEY=1
fi
if [[ $DIRTYKEY -eq 1 ]] ; then
	echo
	echo "$LEADER Copying key.gpg to /usbboot/..."
	cp -v /boot/overlay/key.gpg /usbboot/key.gpg
	if [[ $? -ne 0 ]] ; then
		echo "Error: copy key.gpg to /usbboot/ failed"
		exit 4
	fi
	echo
else
	echo "$LEADER /usbboot/key.gpg is already up-to-date"
fi

cd /usr/src/linux
if [[ $? -ne 0 ]] ; then
	echo "$LEADER Error: failed to cd to /usr/src/linux"
	exit 13
fi

if ! [[ -x /usr/src/linux/usr/gen_init_cpio ]] ; then
	echo -n "$LEADER Building kernel early to get gen_init_cpio... "
	make -j8 >/dev/null
	if [[ $? -ne 0 ]] ; then
		echo "error, make failed"
		exit 14
	fi
	echo ok
fi


echo -n "$LEADER Running genkernel... "
genkernel --lvm --e2fsprogs --disklabel --busybox --luks --gpg \
	--compress-initramfs --compress-initramfs-type=gzip \
	--kernel-config=/usr/src/linux/.config \
	--initramfs-overlay=/boot/overlay/ \
	initramfs >/dev/null
if [[ $? -ne 0 ]] ; then
	echo "error, genkernel failed"
	exit 11
fi
echo ok

VERSIONSTRING=$(readlink -f /usr/src/linux | sed -E 's:/usr/src/linux\-(.*\-gentoo):\1:')

echo "$LEADER Computed VERSIONSTRING: ${VERSIONSTRING}"

echo -n "$LEADER Checking VERSIONSTRING sanity... "
if ! [[ -d /usr/src/linux-${VERSIONSTRING} ]] ; then
	echo "error, could not find matching kernel src dir"
	exit 10
fi
echo ok

echo
echo "$LEADER Copying initramfs to kernel src dir... "
cp -v /boot/initramfs-genkernel-x86_64-${VERSIONSTRING} /usr/src/linux/usr/initramfs_data.cpio.gz
if [[ $? -ne 0 ]] ; then
	echo "Error: copy failed"
	exit 12
fi
echo

echo -n "$LEADER (Re)building kernel with new initramfs_data... "
make -j8 >/dev/null
if [[ $? -ne 0 ]] ; then
	echo "error, make failed"
	exit 14
fi
echo ok

echo -n "$LEADER Building & installing kernel modules... "
make modules_install >/dev/null
if [[ $? -ne 0 ]] ; then
	echo "error, make modules_install failed"
	exit 14
fi
echo ok

echo -n "$LEADER Installing kernel... "
make install >/dev/null
if [[ $? -ne 0 ]] ; then
	echo "error, make install failed"
	exit 14
fi
echo ok

echo
echo "$LEADER Copying kernel image to /usbboot/ destinations..."
cp -v /boot/vmlinuz-${VERSIONSTRING} /usbboot/
if [[ $? -ne 0 ]] ; then
	echo "Error: copy to /usbboot/ failed"
	exit 15
fi

cp -v /boot/vmlinuz-${VERSIONSTRING} /usbboot/EFI/Boot/bootx64.efi
if [[ $? -ne 0 ]] ; then
	echo "Error: copy to /usbboot/EFI/Boot/bootx64.efi failed"
	exit 16
fi
echo

echo "$LEADER Copying config & build script to /usbboot/..."
cp -v /boot/config-${VERSIONSTRING} /usbboot/
if [[ $? -ne 0 ]] ; then
	echo "Error: config copy failed"
	exit 17
fi

cp -v $THISSCRIPT /usbboot/build.sh.bak
if [[ $? -ne 0 ]] ; then
	echo "Error: build.sh.bak copy failed"
	exit 17
fi

chmod -x /usbboot/build.sh.bak >/dev/null 2>/dev/null
echo

echo -n "$LEADER Syncing filesystems... "
sync
if [[ $? -ne 0 ]] ; then
	echo "warning: exited with error; investigate before unplugging USB stick"
fi
echo ok

echo
echo "$LEADER DONE!"
echo
