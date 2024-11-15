if [ -z "$1" ]; then
    echo "Usage: $0 <host>"
    exit 1
fi

HOST=$1
USER=${USER:-bazzite}

# openssl req -new -x509 -newkey rsa:2048 -keyout "key.pem" \
#         -outform DER -out "cert.der" -nodes -days 36500 \
#         -subj "/CN=antheas/"
# openssl x509 -in cert.der -inform DER -outform PEM -out key.cert.pem

# scp cert.der $host:/tmp/cert.der
# sudo mokutil --import "/tmp/cert.der"

make binrpm-pkg -j $(nproc)
# sudo sbsign --key key.pem --cert key.cert.pem ./arch/x86/boot/bzImage --output vmlinuz

# scp vmlinuz $HOST:/tmp/vmlinuz

# ssh $HOST /bin/bash << EOF
#     sudo cp /tmp/vmlinuz /boot/vmlinuz
#     sed -E 's#linux /ostree/.+\$#linux /vmlinuz#g' \
#         /boot/loader/entries/ostree-2.conf | \
#         sed -E 's#^title #title Kernel Swap of #g' | \
#         sed -E 's#^version \\d#version 200#g' | \
#         sudo tee /boot/loader/entries/ostree-100.conf
#     sudo reboot
# EOF
