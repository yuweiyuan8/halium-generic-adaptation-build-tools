# Disclaimer

aarch64 host support is currently experimental, expect features to be missing.

# Build dependencies

Debian:
```sh
sudo apt install -y device-tree-compiler llvm clang gcc lld gcc-arm-linux-gnueabi cpio android-sdk-libsparse-utils libncurses-dev gawk flex bison openssl libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf
```

RedHat:
```sh
sudo dnf install -y dtc llvm clang gcc lld gcc-arm-linux-gnueabi android-tools cpio ncurses-devel gawk flex bison openssl openssl-devel dkms elfutils-libelf-devel libudev-devel pciutils-devel binutils-devel autoconf
```
