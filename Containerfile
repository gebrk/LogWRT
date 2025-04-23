FROM quay.io/fedora/fedora:latest
# Install Imagebuilder deps and LogWRT build requirements
RUN dnf install -y git \
    gawk \
    gettext \
    ncurses-devel \
    zlib-devel \
    openssl-devel \
    libxslt \
    wget \
    which \
    @c-development \
    @development-tools \
    @development-libs \
    zlib-static \
    python3 \
    perl \
    signify \
    just

#USER build
RUN mkdir /build

WORKDIR /build
ENTRYPOINT ["/usr/bin/just"]
