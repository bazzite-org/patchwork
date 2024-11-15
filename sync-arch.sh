# if [ -z "$1" ]; then
#     echo "Usage: $0 <host>"
#     exit 1
# fi

HOST=tbx
USER=${USER:-dev}

set -e
rm -rf linux-*

time PATH="/usr/lib/ccache/bin:$PATH" CCACHE_DIR=$(pwd)/../cache CCACHE_FILECLONE=1 CCACHE_MAXSIZE=30G make pacman-pkg -j 14
scp linux-*.pkg.tar.zst $HOST:/tmp

ssh $HOST /bin/bash << EOF
    yay --noconfirm -U /tmp/linux-upstream-6* /tmp/linux-upstream-headers-6*
    rm -rf /tmp/linux-upstream-6* /tmp/linux-upstream-headers-6*
    sudo reboot
EOF

