obj-y += selinux.o
obj-y += sepolicy.o
obj-y += rules.o

ccflags-y += -Wno-strict-prototypes -Wno-int-conversion
ccflags-y += -Wno-declaration-after-statement -Wno-unused-function
ccflags-y += -I$(srctree)/security/selinux -I$(srctree)/security/selinux/include
ccflags-y += -I$(objtree)/security/selinux -include $(srctree)/include/uapi/asm-generic/errno.h
ccflags-y += -I$(src) -I$(src)/include

# KSU_NEXT_SUSFS_BRIDGE_V113
ccflags-y += -I$(srctree)/include
