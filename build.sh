#!/usr/bin/env bash
set -e

# Check chat_id and token
[ -z "$chat_id" ] && {
    echo "error: please fill your CHAT_ID secret!"
    exit 1
}
[ -z "$token" ] && {
    echo "error: please fill TOKEN secret!"
    exit 1
}

mkdir android-kernel && cd android-kernel

## Variables
GKI_VERSION="android12-5.10"
USE_LTS_MANIFEST=0
USE_CUSTOM_MANIFEST=1
CUSTOM_MANIFEST_REPO="https://github.com/negroweed/kernel_manifest_android12-5.10" # depends on USE_CUSTOM_MANIFEST
CUSTOM_MANIFEST_BRANCH="main"                                                      # depends on USE_CUSTOM_MANIFEST
WORK_DIR=$(pwd)
KERNEL_IMAGE="$WORK_DIR/out/${GKI_VERSION}/dist/Image"
ANYKERNEL_REPO="https://github.com/negroweed/Anykernel3"
ANYKERNEL_BRANCH="gki"
RANDOM_HASH=$(head -c 20 /dev/urandom | sha1sum | head -c 7)
ZIP_NAME="gki-KVER-KSU-$RANDOM_HASH.zip"
AOSP_CLANG_VERSION="r536225"
LAST_COMMIT_BUILDER=$(git log --format="%s" -n 1)

# Import telegram functions
. ../telegram_functions.sh

## Install needed packages
sudo add-apt-repository universe
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y bc bison build-essential curl flex glibc-source git gnupg gperf imagemagick \
    lib32tinfo6 liblz4-tool libncurses6 libncurses-dev libsdl1.2-dev libssl-dev \
    libwxgtk3.2-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools \
    xsltproc zip zlib1g-dev python3

## Install Google's repo
curl https://storage.googleapis.com/git-repo-downloads/repo -o repo
sudo mv repo /usr/bin
sudo chmod +x /usr/bin/repo

## Clone AnyKernel
if [ -z "$ANYKERNEL_REPO" ]; then
    echo "[ERROR] ANYKERNEL_REPO var is not defined. Fix your build vars."
    exit 1
elif [ -z "$ANYKERNEL_BRANCH" ]; then
    echo "[ERROR] ANYKERNEL_BRANCH var is not defined. Fix your build vars."
    exit 1
fi

git clone --depth=1 $ANYKERNEL_REPO -b $ANYKERNEL_BRANCH $WORK_DIR/anykernel

## Sync kernel manifest
if [ -z "$GKI_VERSION" ]; then
    echo "[ERROR] GKI_VERSION var is not defined. Fix your build vars."
    exit 1
elif echo "$GKI_VERSION" | grep -qi 'lts'; then
    echo "[ERROR] Don't add '-lts' in GKI_VERSION var!. Fix your build vars."
    exit 1
fi

if [ "$USE_CUSTOM_MANIFEST" = 1 ] && [ "$USE_LTS_MANIFEST" = 1 ]; then
    echo "[ERROR] USE_CUSTOM_MANIFEST can't be used together with USE_LTS_MANIFEST. Fix your build vars."
    exit 1
elif [ "$USE_CUSTOM_MANIFEST" = 0 ] && [ "$USE_LTS_MANIFEST" = 1 ]; then
    ~/bin/repo init --depth 1 -u https://android.googlesource.com/kernel/manifest -b common-${GKI_VERSION}-lts
elif [ "$USE_CUSTOM_MANIFEST" = 0 ] && [ "$USE_LTS_MANIFEST" = 0 ]; then
    ~/bin/repo init --depth 1 -u https://android.googlesource.com/kernel/manifest -b common-${GKI_VERSION}
elif [ "$USE_CUSTOM_MANIFEST" = 1 ] && [ "$USE_LTS_MANIFEST" = 0 ]; then
    if [ -z "$CUSTOM_MANIFEST_REPO" ]; then
        echo "[ERROR] USE_CUSTOM_MANIFEST is defined, but CUSTOM_MANIFEST_REPO is not defined. Fix your build vars."
        exit 1
    fi

    if [ -z "$CUSTOM_MANIFEST_BRANCH" ]; then
        echo "[ERROR] USE_CUSTOM_MANIFEST is defined, but CUSTOM_MANIFEST_BRANCH is not defined. Fix your build vars."
        exit 1
    fi
    ~/bin/repo init --depth 1 $CUSTOM_MANIFEST_REPO -b $CUSTOM_MANIFEST_BRANCH
fi

~/bin/repo sync -c -j$(nproc --all) --no-clone-bundle --optimized-fetch

## Extract kernel version, git commit string
cd $WORK_DIR/common
KERNEL_VERSION=$(make kernelversion)
LAST_COMMIT_KERNEL=$(git log --format="%s" -n 1)
cd $WORK_DIR

## Set kernel version in ZIP_NAME
ZIP_NAME=$(echo "$ZIP_NAME" | sed "s/KVER/$KERNEL_VERSION/g")

## extract 
COMPILER_STRING=$($WORK_DIR/prebuilts-master/clang/host/linux-x86/clang-${AOSP_CLANG_VERSION}/bin/clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

## KernelSU setup
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
cd $WORK_DIR/KernelSU
KSU_VERSION=$(git describe --abbrev=0 --tags)
cd $WORK_DIR

## Apply patches
git config --global user.email "eraselk@proton.me"
git config --global user.name "eraselk"

cd $WORK_DIR/common
for p in $WORK_DIR/patches/*; do
    if ! git am -3 <$p; then
        patch -p1 <$p
        git add .
        git am --continue || exit 1
    fi
done
cd $WORK_DIR

text="
*~~~ GKI KSU CI ~~~*
*GKI Version*: \`${GKI_VERSION}\`
*Kernel Version*: \`${KERNEL_VERSION}\`
*KSU Version*: \`${KSU_VERSION}\`
*LTO Mode*: \`${LTO_TYPE}\`
*Host OS*: \`$(lsb_release -d -s)\`
*CPU Cores*: \`$(nproc --all)\`
*Zip Output*:
\`\`\`
${ZIP_NAME}
\`\`\`
*Compiler*:
\`\`\`
${COMPILER_STRING}
\`\`\`
*Last Commit (Builder)*:
\`\`\`
${LAST_COMMIT_BUILDER}
\`\`\`
*Last Commit (Kernel)*:
\`\`\`
${LAST_COMMIT_KERNEL}
\`\`\`
"
send_msg "$text"

## Build GKI
LTO=$LTO_TYPE BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh -j$(nproc --all) | tee $WORK_DIR/build_log.txt

if ! [ -f "$KERNEL_IMAGE" ]; then
    send_msg "Build failed!"
    upload_file "$WORK_DIR/build_log.txt" "Build Log"
else
    ## Zipping
    cd $WORK_DIR/anykernel
    sed -i "s/DUMMY1/$KERNEL_VERSION/g" anykernel.sh
    cp $KERNEL_IMAGE .
    zip -r9 $ZIP_NAME * -x LICENSE
    mv $ZIP_NAME $WORK_DIR
    cd $WORK_DIR

    upload_file "$WORK_DIR/$ZIP_NAME" "GKI $KERNEL_VERSION // KSU $KSU_VERSION"
    upload_file "$WORK_DIR/build_log.txt" "Build Log"

fi
