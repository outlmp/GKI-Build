#!/usr/bin/env bash
set -e

[ -z "$chat_id" ] && {
    echo "error: chat_id"
    ret="exit 1"
}

[ -z "$token" ] && {
    echo "error: token"
    ret="exit 1"
}

eval "$ret"

## variables
WORK_DIR=$(pwd)
IMAGE=$WORK_DIR/out/android12-5.10/dist/Image

## set timezone
sudo rm /etc/localtime
sudo ln -s /usr/share/zoneinfo/Asia/Makassar /etc/localtime

## install needed packages
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y bc bison build-essential curl flex glibc-source git gnupg gperf imagemagick lib32ncurses5-dev lib32readline-dev lib32z1-dev liblz4-tool libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev libwxgtk3.0-gtk3-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev python2

## install google's repo
mkdir ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod 777 ~/bin/repo

## clone anykernel
git clone --depth=1 https://github.com/Asteroid21/Anykernel3 -b gki

## sync manifest
~/bin/repo init -u https://android.googlesource.com/kernel/manifest -b common-android12-5.10-lts
~/bin/repo sync -j$(nproc --all)

## kernelsu
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -

## build gki
LTO=$LTO_TYPE BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh -j$(nproc --all)

## check kernel version
cd $WORK_DIR/common
export kver=$(make kernelversion)
cd $WORK_DIR

## zip name
export date=$(date +"%y%m%d%H%M%S")
export ZIP_NAME="gki-$kver-KSU-$date.zip"

## zipping
cd $WORK_DIR/Anykernel3
sed -i "s/DUMMY1/$kver/g" anykernel.sh
cp $IMAGE .
zip -r9 $ZIP_NAME *
mv $ZIP_NAME $WORK_DIR
cd $WORK_DIR

## upload zip file to telegram
upload_file() {
    local file="$1"
    local msg="$2"

    if [ -f "$file" ]; then
        chmod 777 $file
        curl -s -F document=@$file "https://api.telegram.org/bot$token/sendDocument" \
            -F chat_id="$chat_id" \
            -F "disable_web_page_preview=true" \
            -F "parse_mode=markdown" \
            -F caption="$msg"
    else
        echo "error: File $file not found"
        exit 1
    fi
}

upload_file "$WORK_DIR/$ZIP_NAME" "GKI Kernel KSU // $date"
