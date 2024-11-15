#!/bin/bash

# This script temporarily replaces the kernel in a remote Bazzite system
# over ssh. You need to have passwordless sudo. First, it creates a hotfix
# to be able to store the kernel modules in the image. Then, it creates
# a UKI that is used to temporarily boot the new kernel.

if [ -z "$1" ]; then
    echo "Usage: $0 <host>"
    exit 1
fi

set -e

HOST=$1
RSYNC="rsync -rv --exclude .git --exclude venv --exclude __pycache__'"
USER=${USER:-bazzite}

# openssl req -new -x509 -newkey rsa:2048 -keyout "key.pem" \
#         -outform DER -out "cert.der" -nodes -days 36500 \
#         -subj "/CN=antheas/"
# openssl x509 -in cert.der -inform DER -outform PEM -out key.cert.pem

# scp cert.der $host:/tmp/cert.der
# sudo mokutil --import "/tmp/cert.der"

# Prepare device on a hotfix overlay
ssh -t $HOST sudo touch /usr/tst || \
    ssh $HOST /bin/bash << EOF
sudo rpm-ostree usroverlay --hotfix
if [ \$? -eq 0 ]; then
    echo "Applied overlay, rebooting..."
    sudo reboot
fi
EOF

# Update stock fedora config to make sure modules are compressed
if grep -q 'CONFIG_LOCALVERSION=""' .config; then
    cat >> .config << 'EOF'
CONFIG_LOCALVERSION="-custom"
CONFIG_MODULE_COMPRESS=y
# CONFIG_MODULE_COMPRESS_GZIP is not set
# CONFIG_MODULE_COMPRESS_XZ is not set
CONFIG_MODULE_COMPRESS_ZSTD=y
CONFIG_MODULE_COMPRESS_ALL=y
CONFIG_MODULE_DECOMPRESS=y
CONFIG_MODULE_COMPRESS_ZSTD_LEVEL=19
CONFIG_DEBUG_INFO=y
CONFIG_DEBUG_INFO_SPLIT=y
EOF
fi

# Make kernel
time PATH="/usr/lib/ccache/bin:$PATH" \
    CCACHE_DIR=$(pwd)/../cache CCACHE_FILECLONE=1 \
    CCACHE_MAXSIZE=30G CCACHE_IGNORECONFIG=1 \
    make -j $(expr $(nproc) - 2)

# Sync to out dir
rm -rf out
mkdir -p out
make -j $(expr $(nproc) - 2) install INSTALL_PATH=./out/
# sudo sbsign --key key.pem --cert key.cert.pem ./arch/x86/boot/bzImage --output vmlinuz
make -j $(expr $(nproc) - 2) modules_install INSTALL_MOD_PATH=./out/

KNAME=$(make -s kernelrelease)
$RSYNC --rsync-path="sudo rsync" --delete out/lib/modules/$KNAME/ $HOST:/lib/modules/$KNAME/

# Generate initramfs
ssh $HOST /bin/bash << EOF
sudo /usr/bin/dracut --hostonly --kver "$KNAME" --xz -v --add ostree -f /tmp/cinitramfs.img \
    --omit="plymouth"
sudo chmod 644 /tmp/cinitramfs.img
EOF
scp $HOST:/tmp/cinitramfs.img ./out/initramfs.img

# Create UKI
cmdline=`ssh -t $HOST 'cat /boot/loader/entries/ostree-*.conf' | \
        grep 'options' | tac | head -n1 | sed 's/options //'`
echo "Using cmdline: $cmdline"
if [ -z "$cmdline" ]; then
    echo "Failed to get cmdline"
    exit 1
fi

ukify build --linux ./out/vmlinuz --initrd ./out/initramfs.img \
       --cmdline "$cmdline" --output ./out/ukernel.efi

scp ./out/ukernel.efi $HOST:/tmp/ukernel.efi
ssh $HOST /bin/bash << EOF
    sudo cp /tmp/ukernel.efi /boot/efi/EFI/ukernel.efi
    bootnum=\$(sudo efibootmgr | grep "ukernel.efi" | awk '{print \$1}' | sed 's/Boot//;s/\*//')
    if [ -z "\$bootnum" ]; then
        # FIXME: This only works for nvmes
        eval \$(findmnt -no SOURCE /boot/efi | sed -E 's#(/dev/[a-z0-9]+?)(p)([0-9]+)#DISK=\1 PART=\3#')
        sudo efibootmgr --create-only \
            --disk \$DISK --part \$PART \
            --label "Custom Kernel" \
            --loader /EFI/ukernel.efi
    fi
    bootnum=\$(sudo efibootmgr | grep "ukernel.efi" | awk '{print \$1}' | sed 's/Boot//;s/\*//')
    echo "Boot entry found: \$bootnum"
    sudo efibootmgr --bootnext \$bootnum
    sudo reboot
EOF