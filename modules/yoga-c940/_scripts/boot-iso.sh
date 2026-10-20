#!/usr/bin/env bash
# Boots an ISO in QEMU the way a laptop would (UEFI, as a USB mass-storage
# device) and waits for the system to reach the graphical target.
# Usage: modules/yoga-c940/_scripts/boot-iso.sh path/to/image.iso [timeout-seconds]
set -euo pipefail

iso=$(realpath "$1")
timeout=${2:-600}
work=$(mktemp -d)
trap 'kill "${qemu_pid:-0}" 2>/dev/null || true' EXIT

ovmf=$(nix build --no-link --print-out-paths nixpkgs#OVMF.fd)
qemu=$(nix build --no-link --print-out-paths nixpkgs#qemu_kvm)/bin/qemu-system-x86_64
cp "$ovmf/FV/OVMF_VARS.fd" "$work/vars.fd"
chmod +w "$work/vars.fd"

accel=tcg
if [ -w /dev/kvm ]; then accel=kvm; fi
echo "booting $iso with accel=$accel"

"$qemu" \
  -machine q35 -accel "$accel" -m 4096 -smp 2 \
  -drive "if=pflash,format=raw,readonly=on,file=$ovmf/FV/OVMF_CODE.fd" \
  -drive "if=pflash,format=raw,file=$work/vars.fd" \
  -device qemu-xhci \
  -drive "if=none,id=stick,file=$iso,format=raw,readonly=on" \
  -device usb-storage,drive=stick,bootindex=1 \
  -display none -serial "file:$work/serial.log" -no-reboot &
qemu_pid=$!

deadline=$((SECONDS + timeout))
while [ "$SECONDS" -lt "$deadline" ]; do
  if grep -q "Reached target.*Graphical Interface" "$work/serial.log" 2>/dev/null; then
    echo "OK: reached the graphical target after ${SECONDS}s"
    exit 0
  fi
  if grep -qE "emergency mode|Kernel panic|Failed to mount|Dependency failed for.*sysroot" "$work/serial.log" 2>/dev/null; then
    echo "FAIL: boot error"; tail -n 60 "$work/serial.log"; exit 1
  fi
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    echo "FAIL: QEMU exited early"; tail -n 60 "$work/serial.log"; exit 1
  fi
  sleep 3
done
echo "FAIL: timed out after ${timeout}s"; tail -n 60 "$work/serial.log"; exit 1
