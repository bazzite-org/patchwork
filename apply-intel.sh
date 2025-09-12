set -e

apply() {
        echo "##### $1"
        set -e
        git am --whitespace=fix --3way --ignore-space-change --ignore-whitespace < "../ref/linux-intel/$1"
}

recommit() {
        local patchfile="../ref/linux-intel/$1"
        echo "##### $1"
        # List of fuzz levels to try (start lowest). Adjust as needed.
        for fuzz in 0 1 2 3; do
                echo "==> Trying fuzz=$fuzz"
                # Clean uncommitted changes from previous attempt
                git reset --hard
                # -N: ignore already applied hunks, helps if parts are upstream
                # Avoid -f so we can detect failure via exit status
                if patch -p1 -N -F"$fuzz" < "$patchfile"; then
                        echo "Applied with fuzz=$fuzz"
                        git add -u
                        git commit -m "Recommit $1 (fuzz=$fuzz)"
                        return 0
                else
                        echo "Failed with fuzz=$fuzz"
                fi
        done
        git add -u
        git commit -m "Recommit $1"
}

git am --abort || true
git reset --hard kernel-6.15.7-0

#Serie.clr 01XX: Clear Linux patches
apply 0101-i8042-decrease-debug-message-level-to-info.patch
apply 0102-increase-the-ext4-default-commit-age.patch
apply 0104-pci-pme-wakeups.patch
apply 0106-intel_idle-tweak-cpuidle-cstates.patch
apply 0108-smpboot-reuse-timer-calibration.patch
# recommit 0109-initialize-ata-before-graphics.patch # fail
apply 0111-ipv4-tcp-allow-the-memory-tuning-for-tcp-to-go-a-lit.patch
apply 0112-init-wait-for-partition-and-retry-scan.patch
#Patch0113: 0113-print-fsync-count-for-bootchart.patch
apply 0114-add-boot-option-to-allow-unsigned-modules.patch
apply 0115-enable-stateless-firmware-loading.patch
apply 0116-migrate-some-systemd-defaults-to-the-kernel-defaults.patch
apply 0117-xattr-allow-setting-user.-attributes-on-symlinks-by-.patch
recommit 0118-add-scheduler-turbo3-patch.patch # fail
apply 0120-do-accept-in-LIFO-order-for-cache-efficiency.patch
apply 0121-locking-rwsem-spin-faster.patch
apply 0122-ata-libahci-ignore-staggered-spin-up.patch
apply 0123-print-CPU-that-faults.patch
apply 0125-nvme-workaround.patch
apply 0126-don-t-report-an-error-if-PowerClamp-run-on-other-CPU.patch
apply 0127-lib-raid6-add-patch.patch
recommit 0128-itmt_epb-use-epb-to-scale-itmt.patch
apply 0130-itmt2-ADL-fixes.patch
apply 0131-add-a-per-cpu-minimum-high-watermark-an-tune-batch-s.patch
recommit 0132-prezero-20220308.patch # fail
apply 0133-novector.patch
apply 0134-md-raid6-algorithms-scale-test-duration-for-speedier.patch
apply 0135-initcall-only-print-non-zero-initcall-debug-to-speed.patch
recommit libsgrowdown.patch
recommit kdf-boottime.patch # fail
#Patch0139: adlrdt.patch
recommit epp-retune.patch
recommit 0001-mm-memcontrol-add-some-branch-hints-based-on-gcov-an.patch # fail
recommit 0002-sched-core-add-some-branch-hints-based-on-gcov-analy.patch
apply 0149-select-do_pollfd-add-unlikely-branch-hint-return-pat.patch
apply 0150-select-core_sys_select-add-unlikely-branch-hint-on-r.patch
apply 0136-crypto-kdf-make-the-module-init-call-a-late-init-cal.patch
apply ratelimit-sched-yield.patch
recommit scale-net-alloc.patch
apply 0158-clocksource-only-perform-extended-clocksource-checks.patch
recommit better_idle_balance.patch
apply 0161-ACPI-align-slab-buffers-for-improved-memory-performa.patch
apply 0163-thermal-intel-powerclamp-check-MWAIT-first-use-pr_wa.patch
apply 0164-KVM-VMX-make-vmx-init-a-late-init-call-to-get-to-ini.patch
recommit slack.patch
apply 0166-sched-fair-remove-upper-limit-on-cpu-number.patch
apply 0167-net-sock-increase-default-number-of-_SK_MEM_PACKETS-.patch
recommit cstatedemotion.patch
apply 0173-cpuidle-psd-add-power-sleep-demotion-prevention-for-.patch
apply 0174-memcg-increase-MEMCG_CHARGE_BATCH-to-128.patch
apply 0175-readdir-add-unlikely-hint-on-len-check.patch
#Serie.end