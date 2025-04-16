openwrt_version := "24.10.1"
sigfile := "usign_2410"
TARGET := "x86"
BOARD := "64"
PROFILE := "generic"
imagebuilder := "openwrt-imagebuilder-"+openwrt_version+"-"+TARGET+"-"+BOARD+".Linux-x86_64"
downloadbase := "https://downloads.openwrt.org/releases/"+openwrt_version+"/targets/"+TARGET+"/"+BOARD
builddir := "builds/"+openwrt_version+"/"
filedir := "files"
extra_name := "logwrt"
packages := """
    -dnsmasq \
    -odhcpd-ipv6only \
    -ppp -ppp-mod-ppoe -luci-proto-ppp \
    irqbalance \
    luci-ssl-nginx \
    luci-app-snmpd snmpd \
    mc \
    nano \
    htop \
    wget \
    bash \
    shadow \
    lsblk \
    procps-ng-watch \
    block-mount \
    mount-utils \
    nfdump \
    rsyslog \
    logrotate \
    """
helpintro := """LogWRT build script.

This script can download, verify, and run OpenWRT imagebuilder to create a
LogWRT appliance image.
The default is to build for x86_64, but by overriding the default target, board,
and profile images can be built for other architectures. The x86_64 image can be
emulated in qemu for testing, this is not supported for other arches.

Using the buildfor recipe, any supported recipe can be run for any supported board.
e.g. just buildfor rpi-4 buildimage to build an image for rpi-4.
Supported boards:
 * x86_64 (redundant since this is the main default)
 * rpi-4 (including CM4)
 * rpi-3 (all varients)
 * rpi-2
 * rpi (original Pi plus Zero and Zero W)
"""
# We use a custom init script for nfcapd and rsyslog and do some juggling on firstboot
disabled_services := "nfcapd lw_nfcapd rsyslog lw_rsyslog"

list:
    @echo "{{ helpintro }}"
    @just --list

# Run build recipes for a particular target board.
buildfor FOR *commands:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ "{{FOR}}" == "x86_64" ]]; then
        just {{commands}}
    elif [[ "{{FOR}}" == "rpi-4" ]]; then
        echo "TARGET=bcm27xx BOARD=bcm2711 PROFILE=rpi-4"
        just TARGET=bcm27xx BOARD=bcm2711 PROFILE=rpi-4 {{commands}}
    elif [[ "{{FOR}}" == "rpi-3" ]]; then
        echo "TARGET=bcm27xx BOARD=bcm2710 PROFILE=rpi-3"
        just TARGET=bcm27xx BOARD=bcm2710 PROFILE=rpi-3 {{commands}}
    elif [[ "{{FOR}}" == "rpi-2" ]]; then
        echo "TARGET=bcm27xx BOARD=bcm2709 PROFILE=rpi-2"
        just TARGET=bcm27xx BOARD=bcm2709 PROFILE=rpi-2 {{commands}}
    elif [[ "{{FOR}}" == "rpi" ]]; then
        echo "TARGET=bcm27xx BOARD=bcm2708 PROFILE=rpi"
        just TARGET=bcm27xx BOARD=bcm2708 PROFILE=rpi {{commands}}
    else
        echo "ERROR: unknown/unsupported board {{FOR}}"
        exit 1
    fi

# remove all imagebuilder folders and downloads
cleanall:
    rm -rf openwrt-imagebuilder* sha256sums*

# remove the current imagebuilder folders, downloads, and checkups
clean:
    rm -rf {{imagebuilder}}* sha256sums*

# run make clean in imagebuilder folder
makeclean:
    cd {{imagebuilder}} && make clean

# fetch the current imagebuilder and shasums if not present
fetch:
    #!/usr/bin/env bash
    set -euxo pipefail
    # Skip if imagebuilder download present
    test -f {{imagebuilder}}.tar.xz && echo "Imagebuilder download exists, delete or run just clean  to redownload." && exit 0

    curl -Of {{downloadbase}}/{{imagebuilder}}.tar.zst
    curl -f --remote-name-all {{downloadbase}}/sha256sums{,.sig}

# check the downloaded files with signify and sha256sums
verify: fetch
    signify -V -p {{sigfile}} -m sha256sums
    sha256sum --ignore-missing -c sha256sums

# extract the imagebuilder, removing any existing directories
extract: verify
    rm -rf {{imagebuilder}}/
    tar xf {{imagebuilder}}.tar.zst

# build the image
buildimage:
    test -d {{imagebuilder}} || just TARGET={{TARGET}} BOARD={{BOARD}} PROFILE={{PROFILE}} extract
    cd {{imagebuilder}} && \
    make image PROFILE="{{PROFILE}}" EXTRA_IMAGE_NAME="{{extra_name}}" PACKAGES="{{packages}}" FILES="../{{filedir}}" DISABLED_SERVICES="{{disabled_services}}"

# output a package list with our additional packages included
manifest:
    cd {{imagebuilder}} && \
    make manifest PROFILE="{{PROFILE}}" PACKAGES="{{packages}}"

# launch qmeu in nographic mode with a fresh copy of the rootfs
emulate: mkextradrive
    #!/usr/bin/env bash
    set -euxo pipefail
    TMPDIR=$(mktemp -d)

    SECOND_DRIVE="-drive file=$(realpath extradrive.img),format=raw,snapshot=on"

    # Work on a copy of the built image in a new tempdir
    cp {{imagebuilder}}/bin/targets/{{TARGET}}/{{BOARD}}/openwrt-{{openwrt_version}}-{{extra_name}}-{{TARGET}}-{{BOARD}}-{{PROFILE}}-ext4-combined.img.gz "$TMPDIR"/
    pushd "$TMPDIR"
    gunzip -q openwrt-{{openwrt_version}}-{{extra_name}}-{{TARGET}}-{{BOARD}}-{{PROFILE}}-ext4-combined.img.gz || true
    qemu-system-x86_64 -accel kvm -smp "$(nproc)" -nic user,hostfwd=tcp:127.0.0.1:8443-:443 -nographic -drive file=openwrt-{{openwrt_version}}-{{extra_name}}-{{TARGET}}-{{BOARD}}-{{PROFILE}}-ext4-combined.img,format=raw $SECOND_DRIVE
    popd
    rm -rf "$TMPDIR"

# create the extra drive used for emulation (note requires SUDO)
mkextradrive:
    #!/usr/bin/env bash
    set -euxo pipefail
    # Skip if drive exists
    test -f extradrive.img && exit 0

    truncate extradrive.img -s 100M
    parted -s extradrive.img mklabel msdos mkpart primary ext4 0 100%

    # Can't find a way to do this without root
    LOOPDEV=$(sudo losetup -P -f extradrive.img --show)
    sudo mkfs.ext4 -L logstore "$LOOPDEV"p1
    sudo losetup -d "$LOOPDEV"
