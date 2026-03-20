ARG BASE_CONTAINER="ghcr.io/tzarc/qmk_toolchains:base"

ARG RCODESIGN_VERSION="0.29.0"

FROM ubuntu:noble AS extractor
ARG RCODESIGN_VERSION

RUN apt-get update && apt-get install -y \
    curl xz-utils zstd \
    build-essential autoconf automake libtool pkg-config git \
    libxml2-dev libssl-dev zlib1g-dev libbz2-dev
COPY qmk_toolchain*.tar.zst /tmp/
RUN mkdir -p /qmk/bin && ls -1 /tmp/qmk_toolchain*.tar.zst \
    | grep -P 'target_(linux|windows)' \
    | grep -v 'bootstrap' \
    | xargs -I {} tar axf {} -C /qmk --strip-components=1

RUN curl -fsSLO https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F${RCODESIGN_VERSION}/apple-codesign-${RCODESIGN_VERSION}-x86_64-unknown-linux-musl.tar.gz \
    && tar axf apple-codesign-${RCODESIGN_VERSION}-x86_64-unknown-linux-musl.tar.gz --strip-components=1 \
    && mv rcodesign /qmk/bin/rcodesign

# OpenSSL 3.x removed OpenSSL_add_all_ciphers; export the autoconf cache variable
# so the function-presence check is skipped — xar links correctly without it.
RUN git clone --depth=1 https://github.com/mackyle/xar.git /tmp/xar \
    && cd /tmp/xar/xar \
    && export ac_cv_lib_crypto_OpenSSL_add_all_ciphers=yes \
    && ./autogen.sh \
    && ./configure \
           CPPFLAGS="$(pkg-config --cflags openssl libxml-2.0)" \
           LDFLAGS="$(pkg-config --libs-only-L openssl)" \
           LIBS="$(pkg-config --libs-only-l openssl)" \
    && make \
    && mv src/xar /qmk/bin/xar

RUN git clone --depth=1 https://github.com/hogliux/bomutils.git /tmp/bomutils \
    && cd /tmp/bomutils \
    && make \
    && mv build/bin/mkbom /qmk/bin/mkbom \
    && mv build/bin/lsbom /qmk/bin/lsbom

FROM ${BASE_CONTAINER} AS base
COPY --from=extractor /qmk /qmk
