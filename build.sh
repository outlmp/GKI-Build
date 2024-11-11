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
USE_LTS=1
GKI_VERSION="android12-5.10"
WORK_DIR=$(pwd)
IMAGE="$WORK_DIR/out/${GKI_VERSION}/dist/Image"
TIMEZONE="Asia/Makassar"
ANYKERNEL_REPO="https://github.com/Asteroid21/Anykernel3"
ANYKERNEL_BRANCH="gki"
DATE=$(date +"%y%m%d%H%M%S")
ZIP_NAME="gki-KVER-KSU-$DATE.zip"

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
git clone --depth=1 $ANYKERNEL_REPO -b $ANYKERNEL_BRANCH anykernel

## Sync kernel manifest
if [ "$USE_LTS" = 1 ]; then
    ~/bin/repo init -u https://android.googlesource.com/kernel/manifest -b common-${GKI_VERSION}-lts
else
    ~/bin/repo init -u https://android.googlesource.com/kernel/manifest -b common-${GKI_VERSION}
fi

~/bin/repo sync -j$(nproc --all)

## KernelSU setup
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -

## Apply patches
cd $WORK_DIR/common
for p in $WORK_DIR/patches/*; do
    if ! git am -3 <$p; then
        # Force use fuzzy patch
        patch -p1 <$p
        git add .
        git am --continue
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
cp $IMAGE .
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
