#!/usr/bin/env sh

# For Current GeForce/Quadro/Tesla
# https://rpmfusion.org/Howto/NVIDIA#Current_GeForce.2FQuadro.2FTesla

echo "After the RPM transaction ends, please remember to wait until the kmod has been built. This can take up to 5 minutes on some systems." 

sudo dnf up -y
sudo dnf in akmod-nvidia xorg-x11-drv-nvidia-cuda

echo "Module build started. Once the module is built, \"modinfo -F version nvidia\" should output the version of the driver such as 440.64 and not 'modinfo: ERROR: Module nvidia not found'. If you are not running on the latest kernel, use -k to mention the latest one like in modinfo -F version nvidia -k 6.12.6-200.fc41.x86_64"
