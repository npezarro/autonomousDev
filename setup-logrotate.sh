#!/usr/bin/env bash
# setup-logrotate.sh — Install and configure pm2-logrotate on the VM.
# Run once: ./setup-logrotate.sh
# Prevents disk pressure from crash-looping processes filling the 60GB disk.

set -euo pipefail

VM_HOST="REDACTED_VM_HOST"

echo "Installing pm2-logrotate on $VM_HOST..."
ssh "$VM_HOST" "pm2 install pm2-logrotate" 2>&1

echo "Configuring log rotation limits..."
ssh "$VM_HOST" "pm2 set pm2-logrotate:max_size 50M" 2>&1
ssh "$VM_HOST" "pm2 set pm2-logrotate:retain 5" 2>&1
ssh "$VM_HOST" "pm2 set pm2-logrotate:compress true" 2>&1
ssh "$VM_HOST" "pm2 set pm2-logrotate:dateFormat YYYY-MM-DD_HH-mm-ss" 2>&1
ssh "$VM_HOST" "pm2 set pm2-logrotate:rotateModule true" 2>&1

echo "Done. Current log rotation config:"
ssh "$VM_HOST" "pm2 conf pm2-logrotate" 2>&1
