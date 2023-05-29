openwrt_version := "22.03.5"
sigfile := "usign_2203"
TARGET := "x86"
BOARD := "64"
PROFILE := "generic"
imagebuilder := "openwrt-imagebuilder-"+openwrt_version+"-"+TARGET+"-"+BOARD+".Linux-x86_64"
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
"""
# We use a custom init script for nfcapd and rsyslog and do some juggling on firstboot
disabled_services := "nfcapd lw_nfcapd rsyslog lw_rsyslog"

# completely build a fresh image from download to grabbing the sysupgrade
fullbuild: fetch extract buildimage grabupgrade checksum

list:
    @echo "{{ helpintro }}"
    @just --list

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

    curl -O https://downloads.openwrt.org/releases/{{openwrt_version}}/targets/{{TARGET}}/{{BOARD}}/{{imagebuilder}}.tar.xz
    curl --remote-name-all https://downloads.openwrt.org/releases/{{openwrt_version}}/targets/{{TARGET}}/{{BOARD}}/sha256sums{,.sig}

# check the downloaded files with signify and sha256sums
verify: fetch
    signify -V -p {{sigfile}} -m sha256sums
    sha256sum --ignore-missing -c sha256sums

# extract the imagebuilder, removing any existing directories
extract: verify
    rm -rf {{imagebuilder}}/
    tar xf {{imagebuilder}}.tar.xz

# build the image
buildimage:
    test -d {{imagebuilder}} || just extract
    cd {{imagebuilder}} && \
    make image PROFILE="{{PROFILE}}" EXTRA_IMAGE_NAME="{{extra_name}}" PACKAGES="{{packages}}" FILES="../{{filedir}}" DISABLED_SERVICES="{{disabled_services}}"

# output a package list with our additional packages included
manifest:
    cd {{imagebuilder}} && \
    make manifest PROFILE="{{PROFILE}}" PACKAGES="{{packages}}"

# TODO: make grabimage use the defined output directories

grabimage type:
    cp {{imagebuilder}}/bin/targets/{{TARGET}}/{{BOARD}}/openwrt-{{openwrt_version}}-{{extra_name}}-{{TARGET}}-{{BOARD}}-{{PROFILE}}-{{type}}.img.gz .

# copy the sysupgrade image to the top level, overwriting if needed
grabupgrade:
    @just grabimage ext4-sysupgrade

# copy the factory image to the top level, overwriting if needed
grabfactory:
    @just grabimage ext4-factory

# print the checksum of built images
checksum:
    md5sum openwrt-{{openwrt_version}}-{{extra_name}}-{{TARGET}}-{{BOARD}}*.img.gz

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
