#
# build script for X01BD/X00TD
#
# this script doesn't handle required dependencies, so
# install it first before using this script.
#

SECONDS=0
ZIPNAME="Quantum_Ratibor-$(date '+%Y%m%d-%H%M').zip"

# Set default device target to X00TD if not specified
if [ -z $DEVICE_TARGET ]; then
	export DEVICE_TARGET=X00TD
	echo "INFO: DEVICE_TARGET not set, defaulting to X00TD"
fi

echo "INFO: Device target to build: $DEVICE_TARGET"

# Handle: cp $(pwd)/rsuntk-X01BD_defconfig arch/arm64/configs
[ "USE_PERSONAL_DEFCONFIG" = "true" ] && DEFCONFIG="rsuntk-$(echo $DEVICE_TARGET)_defconfig" || DEFCONFIG="asus/$(echo $DEVICE_TARGET)_defconfig"

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
	ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8).zip"
fi

# Check and download clang if not exists
if ! [ -d "$HOME/clang" ]; then
echo "INFO: Clang toolchain not found! Fetching..."
aria2c -o clang-r563880.tar.gz https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/20052113d2a5552cfff78ac7b21fd7953cc1c592/clang-r563880.tar.gz 2>/dev/null
mkdir ~/clang
tar -xf clang-r563880.tar.gz -C ~/clang
rm -rf clang-r563880.tar.gz
echo "INFO: Successfully fetched clang."
else
echo "INFO: Clang toolchain already exists, skipping download."
fi

# Check and download androidcc-4.9 if not exists
if ! [ -d "$HOME/androidcc-4.9" ]; then
echo "INFO: androidcc-4.9 toolchain not found! Fetching..."
curl -LSs "https://raw.githubusercontent.com/rsuntk/toolchains/refs/heads/README/clone.sh" | bash -s androidcc-4.9
mv androidcc-4.9 ~/androidcc-4.9
echo "INFO: Successfully fetched androidcc-4.9."
else
echo "INFO: androidcc-4.9 toolchain already exists, skipping download."
fi

# Check and download arm-gnu if not exists
if ! [ -d "$HOME/arm-gnu" ]; then
echo "INFO: arm-gnu toolchain not found! Fetching..."
curl -LSs "https://raw.githubusercontent.com/rsuntk/toolchains/refs/heads/README/clone.sh" | bash -s arm-gnu
mv arm-gnu ~/arm-gnu
echo "INFO: Successfully fetched arm-gnu."
else
echo "INFO: arm-gnu toolchain already exists, skipping download."
fi

USER="rsuntk"
HOSTNAME="nobody"

export PATH="$HOME/clang/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/clang/lib"
export BUILD_USERNAME=$USER
export BUILD_HOSTNAME=$HOSTNAME
export KBUILD_BUILD_USER=$USER
export KBUILD_BUILD_HOST=$HOSTNAME
export CROSS_COMPILE="$HOME/androidcc-4.9/bin/aarch64-linux-android-"
export CROSS_COMPILE_ARM32="$HOME/arm-gnu/bin/arm-linux-gnueabi-"
export CROSS_COMPILE_COMPAT=$CROSS_COMPILE_ARM32
export LLVM=1
export LLVM_IAS=1

BUILD_FLAGS="
O=out
ARCH=arm64
CC=clang
LD=ld.lld
AR=llvm-ar
AS=llvm-as
NM=llvm-nm
OBJCOPY=llvm-objcopy
OBJDUMP=llvm-objdump
STRIP=llvm-strip
CLANG_TRIPLE=aarch64-linux-gnu-
"

if [[ $1 = "-r" || $1 = "--regen" ]]; then
mkdir out
make $(echo $BUILD_FLAGS) $DEFCONFIG
cp out/.config arch/arm64/configs/$DEFCONFIG
rm -rf out
echo -e "\nRegened defconfig succesfully!"
exit 0
fi

if [[ $1 = "-c" || $1 = "--clean" ]]; then
echo -e "\nClean build!"
rm -rf out
fi

mkdir -p out
make $(echo $BUILD_FLAGS) $DEFCONFIG -j$(nproc --all)

echo -e "\nStarting compilation...\n"
make -j$(nproc --all) $(echo $BUILD_FLAGS) Image.gz-dtb

if [ -f "out/arch/arm64/boot/Image.gz-dtb" ]; then
echo -e "\nINFO: Kernel compiled succesfully! Zipping up...\n"
git clone -q https://github.com/ikwfahmi/AnyKernel3 --single-branch -b 419
cp out/arch/arm64/boot/Image.gz-dtb AnyKernel3
cd AnyKernel3
zip -r9 "../$ZIPNAME" * -x '*.git*' README.md *placeholder
cd ..
if [ "$DO_CLEAN" = "true" ]; then 
rm -rf AnyKernel3 out/arch/arm64/boot
fi
echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
echo "INFO: Output Zip: $ZIPNAME"
exit 0
else
echo -e "\nERROR: Compilation failed!"
exit 1
fi