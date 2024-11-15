if [ -z "$1" ]; then
    echo "Usage: $0 <module> <host>"
    exit 1
fi

set -e

DHOST=$2
DUSER=${DUSER:-bazzite}

# Get directory from module
DIR=$(dirname "$1")
# Get module without .ko suffix
MODULE=$(basename "$1")
MODULE=${MODULE%.ko}
MPATH=$1

make -C /lib/modules/$(uname -r)/build M=$(pwd)/$DIR $MODULE.ko -j $(expr $(nproc) - 2)

scp $MPATH $DHOST:/tmp/$MODULE.ko

ssh $DHOST /bin/bash << EOF
        sudo rmmod $MODULE || true
        sudo insmod /tmp/$MODULE.ko
EOF