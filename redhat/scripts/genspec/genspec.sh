#!/bin/bash
# shellcheck disable=SC2153

UPSTREAM=$(git rev-parse -q --verify ark/"${UPSTREAM_BRANCH}" || \
	   git rev-parse -q --verify origin/"${UPSTREAM_BRANCH}" || \
	   git rev-parse -q --verify "${UPSTREAM_BRANCH}")

if [ -n "$DISTLOCALVERSION" ]; then
	SPECBUILDID=$(printf "%%define buildid %s" "$DISTLOCALVERSION")
else
	SPECBUILDID="# define buildid .local"
fi

# The SPECRELEASE variable uses the SPECBUILDID variable which is
# defined above.  IOW, don't remove SPECBUILDID ;)
SPECRELEASE="${UPSTREAMBUILD}""${BUILD}""%{?buildid}%{?dist}"

EXCLUDE_FILES=":(exclude,top).get_maintainer.conf \
		:(exclude,top).gitattributes \
		:(exclude,top).gitignore \
		:(exclude,top).gitlab-ci.yml \
		:(exclude,top)makefile \
		:(exclude,top)Makefile.rhelver \
		:(exclude,top)redhat \
		:(exclude,top)configs"

FMARKER=$(git log --format="%h" --grep "\[redhat\] kernel-" -1)

# If PATCHLIST_URL is not set to "none", generate Patchlist.changelog file that
# holds the shas and commits not included upstream and git commit url.
SPECPATCHLIST_CHANGELOG=0
if [ "$PATCHLIST_URL" != "none" ]; then
	# sed convert
	# <sha> <description>
	# to
	# <ark_commit_url>/<sha>
	#  <sha> <description>
	#
	# May need to preserve word splitting in EXCLUDE_FILES
	# shellcheck disable=SC2086
	git log --no-merges --pretty=oneline --no-decorate ${UPSTREAM}.."$FMARKER" $EXCLUDE_FILES | \
		sed "s!^\([^ ]*\)!$PATCHLIST_URL/\1\n &!; s!\$!\n!" \
		>> "$SOURCES"/Patchlist.changelog
	SPECPATCHLIST_CHANGELOG=1
fi

EVDIVERSION=$(sed -n 's/MODVER=[[:space:]]*//p' $TOPDIR/drivers/custom/evdi/module/Makefile)

# self-test begin
test -f "$SOURCES/$SPECFILE" &&
	sed -i -e "
	s/%%SPECBUILDID%%/$SPECBUILDID/
	s/%%SPECKVERSION%%/$SPECKVERSION/
	s/%%SPECKPATCHLEVEL%%/$SPECKPATCHLEVEL/
	s/%%SPECBUILD%%/$SPECBUILD/
	s/%%SPECRELEASE%%/$SPECRELEASE/
	s/%%SPECRELEASED_KERNEL%%/$SPECRELEASED_KERNEL/
	s/%%SPECINCLUDE_FEDORA_FILES%%/$SPECINCLUDE_FEDORA_FILES/
	s/%%SPECINCLUDE_RHEL_FILES%%/$SPECINCLUDE_RHEL_FILES/
	s/%%SPECPATCHLIST_CHANGELOG%%/$SPECPATCHLIST_CHANGELOG/
	s/%%SPECINCLUDE_RT_FILES%%/$SPECINCLUDE_RT_FILES/
	s/%%SPECINCLUDE_AUTOMOTIVE_FILES%%/$SPECINCLUDE_AUTOMOTIVE_FILES/
	s/%%SPECVERSION%%/$SPECVERSION/
	s/%%SPECRPMVERSION%%/$SPECRPMVERSION/
	s/%%SPECKABIVERSION%%/$SPECKABIVERSION/
	s/%%SPECTARFILE_RELEASE%%/$SPECTARFILE_RELEASE/
	s/%%SPECPACKAGE_NAME%%/$SPECPACKAGE_NAME/
	s/%%SPECGEMINI%%/$SPECGEMINI/
	s/%%EVDIVERSION%%/$EVDIVERSION/
	s/%%NVIDIAVERSION%%/$NVIDIAVERSION/
	s/%%NVIDIAVERSIONLTS%%/$NVIDIAVERSIONLTS/
	s/%%ZFSVERSION%%/$ZFSVERSION/
	s/%%SPECSELFTESTS_MUST_BUILD%%/$SPECSELFTESTS_MUST_BUILD/" "$SOURCES/$SPECFILE"
test -n "$RHSELFTESTDATA" && test -f "$SOURCES/$SPECFILE" && sed -i -e "
	/%%SPECCHANGELOG%%/r $SOURCES/$SPECCHANGELOG
	/%%SPECCHANGELOG%%/d" "$SOURCES/$SPECFILE"
# self-test end

# We depend on work splitting of BUILDOPTS
# shellcheck disable=SC2086
for opt in $BUILDOPTS; do
	add_opt=
	[ -z "${opt##+*}" ] && add_opt="_with_${opt#?}"
	[ -z "${opt##-*}" ] && add_opt="_without_${opt#?}"
	[ -n "$add_opt" ] && sed -i "s/^\\(# The following build options\\)/%define $add_opt 1\\n\\1/" "$SOURCES/$SPECFILE"
done

# The self-test data doesn't currently have tests for the changelog or patch file, so the
# rest of the script can be ignored.  See redhat/Makefile setup-source target for related
# test changes.
if [ -n "$RHSELFTESTDATA" ]; then
	exit 0
fi

clogf=$(mktemp)
trap 'rm -f "$clogf" "$clogf".stripped' SIGHUP SIGINT SIGTERM EXIT
"${0%/*}"/genlog.sh "$clogf"

cat "$clogf" "$SOURCES/$SPECCHANGELOG" > "$clogf.full"
mv -f "$clogf.full" "$SOURCES/$SPECCHANGELOG"

# genlog.py generates Resolves lines as well, strip these from RPM changelog
grep -v -e "^Resolves: " "$SOURCES/$SPECCHANGELOG" > "$clogf".stripped

test -f "$SOURCES/$SPECFILE" &&
	sed -i -e "
	/%%SPECCHANGELOG%%/r $clogf.stripped
	/%%SPECCHANGELOG%%/d" "$SOURCES/$SPECFILE"

git diff -p --binary --no-renames --stat "$MARKER".."$FMARKER" $EXCLUDE_FILES \
	> ${SOURCES}/patch-1-redhat.patch
git format-patch --stdout --zero-commit -k "$FMARKER"  --no-renames -- $EXCLUDE_FILES \
	> ${SOURCES}/patch-2-handheld.patch

rm -rf ${SOURCES}/patch-3-akmods.patch
# loop through directories in drivers/custom
EMPTY_TREE=$(git hash-object -t tree /dev/null)
INCLUDE_FILES=("*.c" "*.h" "Makefile" "Kconfig" "Kbuild")

cp "$TOPDIR/drivers/custom/broadcom-wl/lib/wlc_hybrid.o_shipped" "$SOURCES/broadcom-wl.blob"

touch ${SOURCES}/patch-3-akmods.patch
for dir in $(find $ "$TOPDIR/drivers/custom" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort || echo ""); do
        SUBDIR=""
	EXTRA_FILES=()

        # Certain modules use subpaths, skip the rest of the repo
        # Those are xpadneo, and razer
        modname=$(basename "$dir")
        if [[ "$modname" == "t150" ]]; then
		SUBDIR="hid-t150/"
		EXTRA_FILES+=("files/etc/udev/rules.d/10-t150.rules")
        elif [[ "$modname" == "xonedo" ]]; then
                EXTRA_FILES+=("install/modprobe.conf")
        elif [[ "$modname" == "razer" ]]; then
                SUBDIR="driver/"
		EXTRA_FILES+=("install_files/udev/*")
	elif [[ "$modname" == "v4l2loopback" ]]; then
		EXTRA_FILES="utils/*"
        elif [[ "$modname" == "evdi" || "$modname" == "kvfm" ]]; then
                SUBDIR="module/"
        elif [[ "$modname" == "cdemu" ]]; then
                SUBDIR="vhba-module/"
		EXTRA_FILES+=("vhba-module/debian/vhba-dkms.udev")
	elif [[ ${modname,,} == nvidia* || "$modname" == "zfs" ]]; then
		# Skip NVIDIA/ZFS modules
		continue
        fi

	# Build FILTER by excluding patterns (optionally within SUBDIR) so only
	# needed files (minus excluded ones) are diffed.
	FILTER=()
	for pat in "${INCLUDE_FILES[@]}"; do
		FILTER+=("$SUBDIR$pat" "$SUBDIR**/$pat")
	done
	FILTER+=("${EXTRA_FILES[@]}")

	# Join array elements into a space-separated list (needed for: -- $FILTER)
	FILTER="${FILTER[@]}"

	# If git is tagged, use tag for version, otherwise short hash
	if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		if MODULE_VERSION=$(git -C "$dir" describe --tags --exact-match 2>/dev/null); then
			:
		else
			MODULE_VERSION=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo Unknown)
		fi
	else
		MODULE_VERSION=Unknown
	fi

	{
		printf '# ----------------------------------------\n'
		printf '# Module: %s\n' "$modname"
		printf '# Version: %s\n' "$MODULE_VERSION"
		printf '# ----------------------------------------\n'
	} >> "${SOURCES}/patch-3-akmods.patch"
	git -C $dir diff "$EMPTY_TREE"..HEAD \
		--binary --no-renames \
		--src-prefix=a/${dir#"$TOPDIR"/}/ \
		--dst-prefix=b/${dir#"$TOPDIR"/}/ \
		-- $FILTER >> ${SOURCES}/patch-3-akmods.patch
done