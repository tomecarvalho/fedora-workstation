#!/usr/bin/env sh

# https://rpmfusion.org/Howto/Secure%20Boot

if ! bootctl status | grep -qi "Secure Boot:.*enabled"; then
  echo "Secure Boot is disabled. Enable it in the BIOS/UEFI settings and try again."
  exit 0
fi

sudo dnf up -y
sudo dnf in -y kmodtool akmods mokutil openssl
sudo kmodgenca -a
echo 'Choose a password for MOK enrollment. Once the system reboots, choose "Enroll MOK", "Continue", then "Yes" and enter the password.'
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
