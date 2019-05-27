#!/bin/sh

# Allow script to be run from another dir
cd "$(dirname "$0")"

# Set terminal color escape sequences
END="\033[0m"
RED="\033[31;1m"
YELLOW="\033[33;1m"
GREEN="\033[32;1m"

BUILD_TYPE="full"
# Set a variable if we only want to build an upgrade archive
if [ "$1" = "upgrade" ] || [ "$1" = "UPGRADE" ]; then
    BUILD_UPGRADE=1
    BUILD_TYPE="upgrade"
fi

# Check if the user has set their ARM toolchain name
if [ -z "$CROSS_TC" ]; then
    printf "%bCROSS_TC variable is not set! Please set it before running this script! Eg: CROSS_TC=\"arm-kobo-linux-gnueabihf\"%b\n" "${RED}" "${END}"
    exit 1
fi

# Then check if the toolchain is in the $PATH
if ! command -v "${CROSS_TC}-gcc"; then
    printf "%bARM toolchain not found! Please add to PATH\n%b\n" "${RED}" "${END}"
    exit 1
fi

export GOOS=linux
export GOARCH=arm
export CGO_ENABLED=1

export CC="${CROSS_TC}-gcc"
export CXX="${CROSS_TC}-g++"

# Setup out directory structure
mkdir -p ./Build/prerequisites/output
rm -rf ./Build/onboard

mkdir -p ./Build/onboard/.adds/kobo-uncaged/bin
mkdir -p ./Build/onboard/.adds/kobo-uncaged/scripts
mkdir -p ./Build/onboard/.adds/kobo-uncaged/config
# Only make the following directories if we are not building an upgrade package
if [ -z $BUILD_UPGRADE ]; then
    mkdir -p ./Build/onboard/.adds/kobo-uncaged/fonts
    mkdir -p ./Build/onboard/.adds/kfmon/config
fi
cd ./Build/prerequisites || exit 1

# Retrieve and build FBInk, if required
if [ ! -f ./output/fbink ] && [ ! -f ./output/button_scan ]; then
    printf "%bFBInk binaries not found. Building from source%b\n" "${YELLOW}" "${END}"
    if [ ! -d ./FBInk ]; then
        git clone --recursive --branch master https://github.com/NiLuJe/FBInk.git
    fi
    cd ./FBInk || exit 1
    make clean
    # Build the standard build first for button_scan
    if ! make; then
        printf "%bMake failed to build 'button_scan'. Aborting%b\n" "${RED}" "${END}"
        exit 1
    fi
    cp ./Release/button_scan ../output/button_scan
    # Clean for minimal build
    make clean
    if ! make MINIMAL=1; then
        printf "%bMake failed to build 'fbink'. Aborting%b\n" "${RED}" "${END}"
        exit 1
    fi
    cp ./Release/fbink ../output/fbink
    cd -
    printf "%bFBInk binaries built%b\n" "${GREEN}" "${END}"
fi

# Next, obtain a TTF font. LiberationSans in our case
if [ ! -f ./output/LiberationSans-Regular.ttf ]; then
    printf "%bFont not found. Downloading LiberationSans%b\n" "${YELLOW}" "${END}"
    wget https://github.com/liberationfonts/liberation-fonts/files/2926169/liberation-fonts-ttf-2.00.5.tar.gz
    tar -zxf ./liberation-fonts-ttf-2.00.5.tar.gz liberation-fonts-ttf-2.00.5/LiberationSans-Regular.ttf
    cp ./liberation-fonts-ttf-2.00.5/LiberationSans-Regular.ttf ./output/LiberationSans-Regular.ttf
    printf "%bLiberationSans-Regular.ttf downloaded%b\n" "${GREEN}" "${END}"
fi
# Back to the top level Build directory
cd ..
# Now that we have everything, time to build Kobo-UNCaGED
printf "%bBuilding Kobo-UNCaGED%b\n" "${YELLOW}" "${END}"
cd ./onboard/.adds/kobo-uncaged/bin || exit 1
ku_vers="$(git describe --tags)"
go_ldflags="-s -w -X main.kuVersion=${ku_vers}"
if ! go build -ldflags "$go_ldflags" ../../../../../kobo-uncaged; then
    printf "%bGo failed to build kobo-uncaged. Aborting%b\n" "${RED}" "${END}"
    exit 1
fi
cd -
printf "%bKobo-UNCaGED built%b\n" "${GREEN}" "${END}"

# Copy the kobo-uncaged scripts to the build directory
cp ../scripts/start-ku.sh ./onboard/.adds/kobo-uncaged/start-ku.sh
cp ../scripts/run-ku.sh ./onboard/.adds/kobo-uncaged/scripts/run-ku.sh
cp ../scripts/nickel-usbms.sh ./onboard/.adds/kobo-uncaged/scripts/nickel-usbms.sh

# Default config file
cp ../kobo-uncaged/ku.toml ./onboard/.adds/kobo-uncaged/config/ku.toml.default

if [ -z BUILD_UPGRADE ]; then
    # FBInk binaries
    cp ./prerequisites/output/fbink ./onboard/.adds/kobo-uncaged/bin/fbink
    cp ./prerequisites/output/button_scan ./onboard/.adds/kobo-uncaged/bin/button_scan
    # Font
    cp ./prerequisites/output/LiberationSans-Regular.ttf ./onboard/.adds/kobo-uncaged/fonts/LiberationSans-Regular.ttf
    # And the kfmon files
    cp ../kfmon/kobo-uncaged.ini ./onboard/.adds/kfmon/config/kobo-uncaged.ini
    cp ../kfmon/Kobo-UNCaGED.png ./onboard/Kobo-UNCaGED.png
fi

# Finally, zip it all up
printf "%bCreating release archive%b\n" "${YELLOW}" "${END}"
cd ./onboard || exit 1
if ! zip -r "../KoboUncaged-${ku_vers}-${BUILD_TYPE}.zip" .; then
    printf "%bFailed to create zip archive. Aborting%b\n" "${RED}" "${END}"
    exit 1
fi
cd -
printf "%b./Build/KoboUncaged-${ku_vers}-${BUILD_TYPE}.zip built%b\n" "${GREEN}" "${END}"
