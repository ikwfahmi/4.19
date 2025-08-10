#
# build script for X01BD/X00TD with KPM patch support
#
# this script doesn't handle required dependencies, so
# install it first before using this script.
#
# KPM patch will be automatically applied if CONFIG_KPM=y is set in kernel config
#

SECONDS=0
ZIPNAME="Quantum-Rift-$(date '+%Y%m%d-%H%M').zip"

# Auto cleanup by default (can be disabled with DO_CLEAN=false)
[ -z "$DO_CLEAN" ] && DO_CLEAN="true"

# Cleanup function
cleanup_repo() {
    echo -e "\nINFO: Cleaning up repository...\n"
    rm -rf AnyKernel3 2>/dev/null || true
    rm -rf out/arch/arm64/boot 2>/dev/null || true
    # Clean up patch_linux if exists
    rm -f out/arch/arm64/boot/patch_linux 2>/dev/null || true
    
    if [ "$DO_CLEAN" = "true" ]; then
        echo "INFO: Performing deep cleanup..."
        rm -rf out 2>/dev/null || true
        # Clean temporary files but preserve zip files
        find . -maxdepth 1 -name "*.jar" -delete 2>/dev/null || true
        find . -maxdepth 1 -name "*.tar.gz" -delete 2>/dev/null || true
        # Only clean untracked files, not tracked ones, but exclude zip files
        git clean -fd --exclude="*.zip" 2>/dev/null || true
        echo "INFO: Deep cleanup completed (zip files preserved)!"
    fi
}

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

USER="kyura"
HOSTNAME="kyuraproject"

# Define directories
KERNEL_DIR="$(pwd)"
OUT_DIR="$KERNEL_DIR/out"
KERNEL_IMAGE_DIR="$OUT_DIR/arch/arm64/boot"

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

if [[ $1 = "--cleanup" ]]; then
echo -e "\nManual cleanup requested!"
cleanup_repo
echo -e "Cleanup completed!"
exit 0
fi

mkdir -p out
make $(echo $BUILD_FLAGS) $DEFCONFIG -j$(nproc --all)

echo -e "\nStarting compilation...\n"
make -j$(nproc --all) $(echo $BUILD_FLAGS) Image.gz-dtb

if [ -f "out/arch/arm64/boot/Image.gz-dtb" ]; then
echo -e "\nINFO: Kernel compiled succesfully!\n"

#=============================#
#      PATCH KPM IF ENABLED   #
#=============================#

# Patch kmp only if CONFIG_KPM=y
if grep -q "^CONFIG_KPM=y" "$OUT_DIR/.config"; then
    echo -e "\nINFO: CONFIG_KPM=y detected, applying KPM patch...\n"
    cd "$KERNEL_IMAGE_DIR"

    # Download latest patch_linux
    echo "INFO: Downloading latest patch_linux..."
    LATEST_PATCH_URL=$(curl -s https://api.github.com/repos/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/latest \
        | grep "browser_download_url" \
        | grep "patch_linux" \
        | cut -d '"' -f 4)
    
    if [ -n "$LATEST_PATCH_URL" ]; then
        curl -L -o patch_linux "$LATEST_PATCH_URL"
        echo "INFO: patch_linux downloaded successfully"
        
        # Run patch
        chmod +x patch_linux
        echo "INFO: Running KPM patch..."
        ./patch_linux
        
        if [ -f "oImage" ]; then
            # Replace Image with patched oImage
            echo "INFO: Replacing Image with patched oImage..."
            rm -f Image Image.gz-dtb
            mv oImage Image

            # Compress and append DTBs
            echo "INFO: Compressing and appending DTBs..."
            gzip -c Image > Image.gz
            cat Image.gz $(find . -name "*.dtb" 2>/dev/null) > Image.gz-dtb 2>/dev/null || cp Image.gz Image.gz-dtb
            
            echo "INFO: KPM patch applied successfully!"
        else
            echo "WARNING: oImage not found after patching, using original Image"
        fi
    else
        echo "WARNING: Failed to get patch_linux download URL, skipping KPM patch"
    fi

    # Back to working directory
    cd "$KERNEL_DIR"
else
    echo "INFO: CONFIG_KPM not enabled, skipping KPM patch"
fi

echo -e "\nINFO: Preparing for zipping...\n"

BUILD_START=$(date +"%s")
ANYKERNEL3_DIR="AnyKernel3"
FINAL_KERNEL_ZIP="${ZIPNAME%.*}"  # Remove .zip extension for processing

git clone -q https://github.com/ikwfahmi/AnyKernel3 --single-branch -b 419
cp out/arch/arm64/boot/Image.gz-dtb AnyKernel3

cd $ANYKERNEL3_DIR || exit 1
zip -r9 "../$FINAL_KERNEL_ZIP.zip" * -x .git README.md ./*placeholder .gitignore zipsigner* *.zip
ZIP_FINAL="$FINAL_KERNEL_ZIP"
cd ..

echo -e "\nINFO: Downloading zipsigner...\n"
curl -sLo zipsigner-3.0.jar https://github.com/Magisk-Modules-Repo/zipsigner/raw/master/bin/zipsigner-3.0-dexed.jar

echo -e "\nINFO: Signing zip...\n"
java -jar zipsigner-3.0.jar "$ZIP_FINAL.zip" "$ZIP_FINAL-signed.zip"

# Remove unsigned zip and keep only signed zip
rm "$ZIP_FINAL.zip"
ZIP_FINAL="$ZIP_FINAL-signed"

# Clean up zipsigner
rm zipsigner-3.0.jar

BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))

# Clean up build artifacts and AnyKernel3
cleanup_repo

echo -e "\nCompleted in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) second(s) !"
echo "INFO: Output Zip (signed): $ZIP_FINAL.zip"
echo "INFO: Repository cleaned successfully!"
exit 0
else
echo -e "\nERROR: Compilation failed!"
cleanup_repo
exit 1
fi