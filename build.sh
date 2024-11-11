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

## Variables
GKI_VERSION="android12-5.10"
USE_LTS_MANIFEST=0
USE_CUSTOM_MANIFEST=1
CUSTOM_MANIFEST_REPO="https://github.com/Asteroid21/kernel_manifest_android12-5.10" # depends on USE_CUSTOM_MANIFEST
CUSTOM_MANIFEST_BRANCH="main" # depends on USE_CUSTOM_MANIFEST
WORK_DIR=$(pwd)
KERNEL_IMAGE="$WORK_DIR/out/${GKI_VERSION}/dist/Image"
TIMEZONE="Asia/Makassar"
ANYKERNEL_REPO="https://github.com/Asteroid21/Anykernel3"
ANYKERNEL_BRANCH="gki"
DATE=$(date +"%y%m%d%H%M%S")
ZIP_NAME="gki-KVER-KSU-$DATE.zip"
CLANG_VERSION="r536225"

## Set timezone
if [ -n "$TIMEZONE" ] && [ -f /usr/share/zoneinfo/$TIMEZONE ]; then
    sudo ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
fi

## Install needed packages
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y bc bison build-essential curl flex glibc-source git gnupg gperf imagemagick \
    lib32ncurses5-dev lib32readline-dev lib32z1-dev liblz4-tool libncurses5 libncurses5-dev \
    libsdl1.2-dev libssl-dev libwxgtk3.0-gtk3-dev libxml2 libxml2-utils lzop pngcrush rsync \
    schedtool squashfs-tools xsltproc zip zlib1g-dev python2

## Install Google's repo
[ ! -d ~/bin ] && mkdir ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo >~/bin/repo
chmod 777 ~/bin/repo

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
fi

if [ "$USE_CUSTOM_MANIFEST" = 1 ] && [ "$USE_LTS_MANIFEST" = 1 ]; then
    echo "[ERROR] USE_CUSTOM_MANIFEST can't be used together with USE_LTS_MANIFEST. Fix your build vars."
    exit 1
elif [ "$USE_CUSTOM_MANIFEST" = 0 ] && [ "$USE_LTS_MANIFEST" = 1 ]; then
    ~/bin/repo init -u https://android.googlesource.com/kernel/manifest -b common-${GKI_VERSION}-lts
elif [ "$USE_CUSTOM_MANIFEST" = 0 ] && [ "$USE_LTS_MANIFEST" = 0 ]; then
    ~/bin/repo init -u https://android.googlesource.com/kernel/manifest -b common-${GKI_VERSION}
elif [ "$USE_CUSTOM_MANIFEST" = 1 ] && [ "$USE_LTS_MANIFEST" = 0 ]; then
    if [ -z "$CUSTOM_MANIFEST_REPO" ]; then
        echo "[ERROR] USE_CUSTOM_MANIFEST is defined, but CUSTOM_MANIFEST_REPO is not defined. Fix your build vars."
        exit 1
    fi
    
    if [ -z "$CUSTOM_MANIFEST_BRANCH" ]; then
        echo "[ERROR] USE_CUSTOM_MANIFEST is defined, but CUSTOM_MANIFEST_BRANCH is not defined. Fix your build vars."
        exit 1
    fi
    ~/bin/repo init $CUSTOM_MANIFEST_REPO -b $CUSTOM_MANIFEST_BRANCH
fi

~/bin/repo sync -j$(nproc --all)

## Clone crdroid's clang
rm -rf $WORK_DIR/prebuilts-master
mkdir -p $WORK_DIR/prebuilts-master/clang/host/linux-x86
git clone --depth=1 https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-${CLANG_VERSION} $WORK_DIR/prebuilts-master/clang/host/linux-x86/clang-${CLANG_VERSION}

## KernelSU setup
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -

## Apply patches
cd $WORK_DIR/common
for p in $WORK_DIR/patches/*; do
    if ! git am -3 <$p; then
        patch -p1 <$p
        git add .
        git am --continue || { echo "[ERROR] Failed to apply patch $p"; exit 1; }
    fi
done
cd $WORK_DIR

## Build GKI
LTO=$LTO_TYPE BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh -j$(nproc --all)

## Extract kernel version
cd $WORK_DIR/common
KERNEL_VERSION=$(make kernelversion)
cd $WORK_DIR

## Set kernel version in ZIP_NAME
ZIP_NAME=$(echo "$ZIP_NAME" | sed "s/KVER/$KERNEL_VERSION/g")

## Zipping
cd $WORK_DIR/anykernel
sed -i "s/DUMMY1/$KERNEL_VERSION/g" anykernel.sh
cp $KERNEL_IMAGE .
zip -r9 $ZIP_NAME *
mv $ZIP_NAME $WORK_DIR
cd $WORK_DIR

## Upload zip file to Telegram
upload_file() {
    local file="$1"
    local msg="$2"

    [ -f "$file" ] && chmod 777 "$file" || {
        echo "error: File $file not found"
        exit 1
    }
    curl -s -F document=@"$file" "https://api.telegram.org/bot$token/sendDocument" \
        -F chat_id="$chat_id" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=markdown" \
        -F caption="$msg"
}

upload_file "$WORK_DIR/$ZIP_NAME" "GKI $KERNEL_VERSION KSU // $DATE"
echo "Build Done!"