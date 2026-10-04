# Out-of-tree build of the patched xpad driver.
#
# Manual build:
#   make -C /lib/modules/$(uname -r)/build M=$PWD modules
#
# DKMS drives this through dkms.conf.

obj-m := xpad.o
