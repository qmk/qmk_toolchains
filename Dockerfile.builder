ARG BASE_CONTAINER="ghcr.io/tzarc/qmk_toolchains:base"

ARG RCODESIGN_VERSION="0.29.0"

FROM ubuntu:noble AS extractor
ARG RCODESIGN_VERSION

RUN apt-get update && apt-get install -y curl xz-utils zstd
COPY qmk_toolchain*.tar.zst /tmp
RUN mkdir -p /qmk/bin && ls -1 /tmp/qmk_toolchain*.tar.zst | xargs -I {} tar axf {} -C /qmk --strip-components=1

RUN curl -fsSLO https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F${RCODESIGN_VERSION}/apple-codesign-${RCODESIGN_VERSION}-x86_64-unknown-linux-musl.tar.gz \
    && tar axf apple-codesign-${RCODESIGN_VERSION}-x86_64-unknown-linux-musl.tar.gz --strip-components=1 \
    && mv rcodesign /qmk/bin/rcodesign

FROM ${BASE_CONTAINER} AS base
COPY --from=extractor /qmk /qmk
