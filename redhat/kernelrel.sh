#!/bin/bash

if [ $# -lt 2 ]
then
        echo "Usage: kernelrel <start> <tag>"
        return
fi

if [ ! -f './sync-arch.sh' ]
then
        echo "No sync-arch.sh script found. Wrong dir"
        return
fi

(
        set -e

        dist=$1 
        relver=$2

        # Make sure relver has a leading 0
        if [ ${#relver} -eq 1 ]; then
                relver="0$relver"
        fi
        relver="ba$relver"

        git -C ../kernel-bazzite pull
        rm -f ./redhat/rpm/SRPMS/kernel-*.src.rpm || true
        make -C redhat dist-clean
        make -C redhat dist-srpm -j $(expr $(nproc) - 2) DIST=$1 BUILD=$relver IS_FEDORA=1
        if [ $(ls ./redhat/rpm/SRPMS/kernel-*.src.rpm 2> /dev/null | wc -l) -ne 1 ]
        then
                echo "No SRPM found after build. Something went wrong."
                exit 1
        fi
        rpm2cpio ./redhat/rpm/SRPMS/kernel-*.src.rpm | cpio -idmv -D ../kernel-bazzite
        tag=$(rpm -qp --qf '%{VERSION}' ./redhat/rpm/SRPMS/kernel-*.src.rpm | sed 's/-/./g')-$relver
        echo Tag: $tag
        git tag -f $tag && git push origin $tag -f
        git -C ../kernel-bazzite add .
        git -C ../kernel-bazzite commit -m "bump to $tag"
        git -C ../kernel-bazzite tag -f $tag
        git -C ../kernel-bazzite push origin $tag -f
        git -C ../kernel-bazzite push
        xdg-open "https://github.com/bazzite-org/kernel-bazzite/releases/new?tag=$tag"
)