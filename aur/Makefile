# Only needed for manual out-of-tree builds; DKMS drives the real build
# through dkms.conf. Do not hardcode LLVM=1 here or in dkms.conf: the
# kernel defaults to gcc and clang/lld are not guaranteed to be installed.
obj-m := xpad.o

all:
	$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
