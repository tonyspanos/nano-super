#!/bin/bash
# nano-oc-dtb.sh - Rebuild the Jetson Nano (P3448-0000 B00, L4T R32.7.x) CPU/GPU
# overclock DTB and register it as the default extlinux boot entry.
#
# Device-tree changes applied to the stock kernel DTB:
#   /clock@70110000           nvidia,dfll-max-freq-khz  -> commented out (removes 1479 MHz CPU cap)
#   /cpufreq/cpu-scaling-data freq-table                 += 1555500 kHz step
#   /dvfs                     nvidia,gpu-max-freq-khz   -> commented out (removes 921.6 MHz GPU cap)
#
# Result: CPU max 1555.5 MHz (was 1479), GPU max 998.4 MHz (was 921.6).
# The stock "primary" entry is kept in extlinux.conf as a fallback (select it on
# the serial console at boot, or run this script with --revert).
#
# Usage: sudo ./nano-oc-dtb.sh [--src stock.dtb] [--dry-run] [--revert]
set -euo pipefail

SRC=/boot/tegra210-p3448-0000-p3449-0000-b00.dtb
OUT=/boot/dtb-oc.dtb
EXTLINUX=/boot/extlinux/extlinux.conf
LABEL=oc
DRY=0
REVERT=0

while [ $# -gt 0 ]; do
    case "$1" in
        --src) SRC="$2"; shift ;;
        --dry-run) DRY=1 ;;
        --revert) REVERT=1 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

die() { echo "error: $*" >&2; exit 1; }
[ "$DRY" = 1 ] || [ "$(id -u)" = 0 ] || die "run as root (or use --dry-run)"

if [ "$REVERT" = 1 ]; then
    sed -i 's/^DEFAULT .*/DEFAULT primary/' "$EXTLINUX"
    echo "extlinux DEFAULT set to primary; reboot to return to stock clocks."
    exit 0
fi

command -v dtc >/dev/null || die "dtc not found (apt install device-tree-compiler)"
[ -f "$SRC" ] || die "source DTB not found: $SRC"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
dtc -I dtb -O dts -q -o "$WORK/stock.dts" "$SRC"

grep -q '^\s*nvidia,dfll-max-freq-khz = <0x169158>;' "$WORK/stock.dts" \
    || die "$SRC does not look like a stock Nano B00 DTB (dfll-max-freq-khz not found)"

sed -E \
    -e 's/^(\s*)(nvidia,dfll-max-freq-khz = <0x169158>;)/\1#\2/' \
    -e 's/^(\s*)(nvidia,gpu-max-freq-khz = <0xe1000>;)/\1#\2/' \
    -e '/^\s*freq-table = <0x18e70 /s/ 0x175890 0x18e700/ 0x175890 0x17bc2c 0x18e700/' \
    "$WORK/stock.dts" > "$WORK/oc.dts"

# Sanity: exactly three lines must differ.
n=$(diff "$WORK/stock.dts" "$WORK/oc.dts" | grep -c '^>' || true)
[ "$n" = 3 ] || die "expected 3 changed lines, got $n"
diff "$WORK/stock.dts" "$WORK/oc.dts" || true

dtc -I dts -O dtb -q -o "$WORK/oc.dtb" "$WORK/oc.dts"

if [ "$DRY" = 1 ]; then
    cp "$WORK/oc.dtb" ./dtb-oc.dtb
    echo "dry run: wrote ./dtb-oc.dtb, /boot untouched"
    exit 0
fi

[ -f "$OUT" ] && cp -a "$OUT" "$OUT.bak"
install -m 644 "$WORK/oc.dtb" "$OUT"
echo "installed $OUT"

cp -a "$EXTLINUX" "$EXTLINUX.bak"
if ! grep -q "^LABEL $LABEL\$" "$EXTLINUX"; then
    # Clone the primary entry's LINUX/INITRD/APPEND and add an FDT line.
    awk -v label="$LABEL" -v fdt="$OUT" '
        /^LABEL primary$/ { inprim=1 }
        inprim && /^[ \t]*LINUX /  { linux=$0 }
        inprim && /^[ \t]*INITRD / { initrd=$0 }
        inprim && /^[ \t]*APPEND / { append=$0; inprim=0 }
        { print }
        /^[ \t]*APPEND / && !done && append != "" {
            print ""
            print "LABEL " label
            print "      MENU LABEL overclock (" fdt ")"
            print linux
            print initrd
            print "      FDT " fdt
            print append
            done=1
        }' "$EXTLINUX.bak" > "$EXTLINUX"
    echo "added LABEL $LABEL to $EXTLINUX"
fi
sed -i "s/^DEFAULT .*/DEFAULT $LABEL/" "$EXTLINUX"
echo "extlinux DEFAULT set to $LABEL (backup: $EXTLINUX.bak). Reboot to apply."
echo "After reboot verify with:"
echo "  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies"
echo "  cat /sys/devices/gpu.0/devfreq/57000000.gpu/available_frequencies"
