#!/bin/sh

# Get script directory
DIR=$(dirname $0)

download_mod() {
    # $1 is name, $2 is url

    # Download the module
    echo ""
    echo "##### Downloading $1"

    # Check if the module is already downloaded
    if [ -d $DIR/$1 ]; then
        echo "$1 is already downloaded"
        rm -rf $DIR/$1
    fi

    if [ -z "$3" ]; then
        git clone --depth=1 $2 $DIR/$1
    else
        git clone --depth=200 $2 $DIR/$1
        git -C $DIR/$1 checkout $3
    fi

    # Get short sha of the module
    SHA=$(git -C $DIR/$1 rev-parse --short HEAD)

    if [ "$1" = "kvfm" ] || [ "$1" = "evdi" ]; then
        # kvfm/evdi is inside module folder
        mv $DIR/$1 $DIR/other
        mv $DIR/other/module $DIR/$1
        rm -rf $DIR/other
    fi

    if [ "$1" = "xpadneo" ]; then
         # xpadneo is inside module folder
        mv $DIR/$1 $DIR/other
        mv $DIR/other/hid-xpadneo $DIR/$1
        rm -rf $DIR/other
    fi

    if [ "$1" = "openrazer" ]; then
         # openrazer is inside module folder
        mv $DIR/$1 $DIR/other
        mv $DIR/other/driver $DIR/$1
        rm -rf $DIR/other
    fi

    # Remove files to minimize diff
    rm -rf $DIR/$1/.git \
        $DIR/$1/.gitignore \
        $DIR/$1/.gitmodules \
        $DIR/$1/.github \
        $DIR/$1/*.spec \
        $DIR/$1/*.md \
        $DIR/$1/*.rst \
        $DIR/$1/VERSION \
        $DIR/$1/docs \
        $DIR/$1/android \
        $DIR/$1/pylib \
        $DIR/$1/daemon \
        $DIR/$1/tests \
        $DIR/$1/.builds \
        $DIR/$1/dkms.conf

    # Add the module to Makefile
    echo "obj-\$(CONFIG_${1^^}) += $1/" >> $DIR/Makefile
    # echo "obj-m += $1/" >> $DIR/Makefile

    # Handle kconfig
    if [ -f $DIR/$1/Kconfig ]; then
        echo "source \"drivers/custom/$1/Kconfig\"" >> $DIR/Kconfig
    else
        echo "config ${1^^}" >> $DIR/Kconfig
        echo "    tristate \"$1\"" >> $DIR/Kconfig
        echo "    help" >> $DIR/Kconfig
        echo "        $1 driver. For more information see:" >> $DIR/Kconfig
        echo "        $2" >> $DIR/Kconfig
    fi
    echo "" >> $DIR/Kconfig

    # If there is no Makefile, create one based on Kbuild (xone)
    if [ ! -f $DIR/$1/Makefile ]; then
        cp $DIR/$1/Kbuild $DIR/$1/Makefile
    fi

    # Commit the changes
    git add $DIR/$1 $DIR/Makefile $DIR/Kconfig
    git commit -m "modules: Add $1 ($SHA)"
}

# Get current hash
HASH=$(git rev-parse --short HEAD)

# Switch to akmods branch
git branch -D akmods &>/dev/null || true
git checkout -b akmods

# Build modules only for x86
echo "ifneq (\$(ARCH),arm64)" > $DIR/Makefile
git add $DIR/Makefile
git commit -m "modules: start arch check"

# Download modules
download_mod "ayn_platform"     "https://github.com/KyleGospo/ayn-platform"
download_mod "ayaneo_platform"  "https://github.com/KyleGospo/ayaneo-platform.git"
download_mod "bmi260"           "https://github.com/KyleGospo/bmi260.git"
download_mod "framework_laptop" "https://github.com/KyleGospo/framework-laptop-kmod.git"
download_mod "xonedo"           "https://github.com/KyleGospo/xonedo.git"
download_mod "xpadneo"          "https://github.com/atar-axis/xpadneo"
download_mod "new_lg4ff"        "https://github.com/berarma/new-lg4ff.git"
download_mod "88xxau"           "https://github.com/morrownr/8814au"
download_mod "rtl8814au"        "https://github.com/aircrack-ng/rtl8812au"
download_mod "nct6687d"         "https://github.com/ublue-os/nct6687d.git"
download_mod "zenergy"          "https://github.com/KyleGospo/zenergy.git"
download_mod "openrazer"        "https://github.com/ublue-os/openrazer.git"
download_mod "gpd_fan"          "https://github.com/KyleGospo/gpd-fan-driver.git"
download_mod "gcadapter_oc"     "https://github.com/hannesmann/gcadapter-oc-kmod"
download_mod "system76"         "https://github.com/pop-os/system76-dkms"
download_mod "system76_io"      "https://github.com/pop-os/system76-io-dkms"
download_mod "kvfm"             "https://github.com/gnif/LookingGlass"
download_mod "drm_evdi"         "https://github.com/DisplayLink/evdi"
download_mod "v4l2loopback"     "https://github.com/umlaeute/v4l2loopback"
download_mod "facetimehd"       "https://github.com/patjak/facetimehd/"

echo "endif" >> $DIR/Makefile
git add $DIR/Makefile
git commit -m "modules: finish arch check"

# CROS_EC=y # for framework kmod
# CONFIG_AYN_PLATFORM=m
# CONFIG_AYANEO_PLATFORM=m
# CONFIG_BMI260=m
# CONFIG_FRAMEWORK_LAPTOP=m
# CONFIG_XONEDO=m
# CONFIG_NEW_LG4FF=m
# CONFIG_RTL8814AU=m
# CONFIG_88XXAU=m
# CONFIG_NCT6687D=m
# CONFIG_ZENERGY=m
# CONFIG_OPENRAZER=m
# CONFIG_GPD_FAN=m

# Pretty print the changes to the file $1 or 0000-akmods.patch if it is not provided
git format-patch --stdout --zero-commit -k $HASH > ${1:-0000-akmods.patch}