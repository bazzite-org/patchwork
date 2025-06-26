#!/bin/bash

# This script updates the os-build-next branch based on merging the current
# os-build branch with the linux-next master branch. Just as linux-next is
# rebased, so will the os-build-next branch.

set -e

DIRPATH="$(dirname "$(realpath "$0")")"

# source common CI functions and variables
# shellcheck disable=SC1091
. "$DIRPATH/ark-ci-env.sh"

FLAVORS=$(cat redhat/configs/flavors)

commit_new_configs()
{
	for flavor in $FLAVORS; do
		make FLAVOR="$flavor" dist-configs-commit
	done
}

commit_mismatches()
{
	for flavor in $FLAVORS; do
		make FLAVOR="$flavor" dist-configs-commit-mismatches
	done
}

# Upstream linux-next tree
LINUX_NEXT_REPO_URL="git://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git"
LINUX_NEXT_REMOTE_NAME="linux-next"
LINUX_NEXT_BRANCH="master"
LINUX_UPSTREAM_BRANCH="master"
KERNEL_ARK_REMOTE_NAME="origin"
# shellcheck disable=SC2034
KERNEL_ARK_MAIN_BRANCH="os-build"
KERNEL_ARK_NEXT_BRANCH="os-build-next"

# verify git remote linux-next is setup
if ! git remote get-url "$LINUX_NEXT_REMOTE_NAME" 2>/dev/null; then
	die "Please 'git remote add $LINUX_NEXT_REMOTE_NAME $LINUX_NEXT_REPO_URL'"
fi

# ensure that we have the upstream master branch (Linus's tree) - we'll need this to help AI resolve merge conflicts
ark_git_mirror "$LINUX_UPSTREAM_BRANCH" "$KERNEL_ARK_REMOTE_NAME" "$LINUX_UPSTREAM_BRANCH"

# switch to kernel-ark's next branch
if ! git rev-parse --verify "$KERNEL_ARK_NEXT_BRANCH" 2>/dev/null; then
	git checkout -b "$KERNEL_ARK_NEXT_BRANCH" "$KERNEL_ARK_REMOTE_NAME/$KERNEL_ARK_NEXT_BRANCH"
else
	git checkout "$KERNEL_ARK_NEXT_BRANCH"
fi

# hard reset the next branch to kernel-ark's main branch
git reset --hard "$KERNEL_ARK_REMOTE_NAME/$KERNEL_ARK_MAIN_BRANCH"

# install the merge driver dependencies
pip install -r "$DIRPATH/requirements.txt"

# configure the merge driver
# git config --local merge.ark-md.name 'kernel-ark merge driver'
# git config --local merge.ark-md.driver "$DIRPATH/ark-merge-driver.py driver --debug --color %O %A %B %L %P"

# set the ark merge driver as the default for all file types
# Because the current merge driver won't be as good as git's ort merge
# strategy, we'll use the merge driver as our merge tool to handle only
# conflicts that git can't resolve.
# echo "* merge=ark-md" > .git/info/attributes

# configure the merge driver as our merge tool
git config --local merge.tool ark-md
git config --local mergetool.ark-md.cmd "$DIRPATH/ark-merge-driver.py mergetool --debug --color \"\$BASE\" \"\$LOCAL\" \"\$REMOTE\" \"\$MERGED\""
git config --local mergetool.ark-md.trustExitCode true
git config --local mergetool.ark-md.guiDefault false
git config --local mergetool.ark-md.prompt false

# add the prepare-commit-msg git hook (which will add a list of files resolved by the merge driver)
cp "$DIRPATH/ark-merge-driver-prepare-commit-msg.sh" .git/hooks/prepare-commit-msg

# merge linux-next to kernel-ark's next branch
git merge --signoff --no-ff --no-edit "$(git describe "$LINUX_NEXT_REMOTE_NAME/$LINUX_NEXT_BRANCH")" || MERGE_RESULT=$?

# if the merge failed, then we'll use the merge driver to resolve the conflicts
if [ "$MERGE_RESULT" -ne 0 ]; then
	git mergetool
	git commit --signoff --no-edit
fi

# generate pending configs for new configs
commit_new_configs

# generate pending configs for mismatches
# Future work: this blindly generates pending configs with no verification or reasoning.
commit_mismatches

# TODO: resolve misconfigured config options
# The following will error on misconfigured config options:
# make PROCESS_CONFIGS_CHECK_OPTS="-w -n -c" dist-configs-check
# To avoid an rpmbuild error, we'll use NO_CONFIGCHECKS=1 when creating the srpm.

# Use the localversion-next file to define the localversion.
# Due to RPM's NVR dash limitation, we must replace dashes and remove the
# localversion-next file to prevent it from being used by the Makefile or it
# would cause an error. The localversion file will be used to define
# DISTLOCALVERSION but it will also be used by the build system to define the
# kernel release (uname -r). That can cause the uname length to exceed the
# limit of 64 characters, so we shorten it by dropping the year.
LOCALVERSION_NEXT=$(cat localversion-next)
echo "$LOCALVERSION_NEXT" | sed -E 's/-next-[0-9]{4}([0-9]{4})$/.next\1/' > localversion
git rm localversion-next
git add -f localversion
git commit -s -m "localversion: change $LOCALVERSION_NEXT to $(cat localversion)"

# push the changes to the next branch
test "$TO_PUSH" && git push -f "$KERNEL_ARK_REMOTE_NAME" "$KERNEL_ARK_NEXT_BRANCH"

exit 0
