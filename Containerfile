# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Build external artifacts in an isolated stage so toolchains never land in the final image.
FROM ghcr.io/ublue-os/bazzite-deck:stable as artifact-builder

ARG SECUREBOOT_MOK_KEY_B64=""
ARG SECUREBOOT_MOK_CERT_B64=""

RUN if grep -Rqs "^\[updates-archive\]" /etc/yum.repos.d; then \
      for f in /etc/yum.repos.d/*.repo; do \
        if grep -q "^\[updates-archive\]" "$f"; then \
          sed -i '/^\[updates-archive\]/,/^\[/ s/^enabled=.*/enabled=0/' "$f"; \
        fi; \
      done; \
    fi || true

RUN if grep -Rqs "^\[terra-mesa\]" /etc/yum.repos.d; then \
      for f in /etc/yum.repos.d/*.repo; do \
        if grep -q "^\[terra-mesa\]" "$f"; then \
          sed -i '/^\[terra-mesa\]/,/^\[/ s/^enabled=.*/enabled=0/' "$f"; \
        fi; \
      done; \
    fi || true

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    SECUREBOOT_MOK_KEY_B64="${SECUREBOOT_MOK_KEY_B64}" \
    SECUREBOOT_MOK_CERT_B64="${SECUREBOOT_MOK_CERT_B64}" \
    bash /ctx/build-modules.sh

# Base Image
FROM ghcr.io/ublue-os/bazzite-deck:stable as bazzite-zone-deck

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
#
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## Disable repos that have recently caused FC43 depsolve failures.
RUN if grep -Rqs "^\[updates-archive\]" /etc/yum.repos.d; then \
      for f in /etc/yum.repos.d/*.repo; do \
        if grep -q "^\[updates-archive\]" "$f"; then \
          sed -i '/^\[updates-archive\]/,/^\[/ s/^enabled=.*/enabled=0/' "$f"; \
        fi; \
      done; \
    fi || true

# terra-mesa Repo deaktivieren
RUN if grep -Rqs "^\[terra-mesa\]" /etc/yum.repos.d; then \
      for f in /etc/yum.repos.d/*.repo; do \
        if grep -q "^\[terra-mesa\]" "$f"; then \
          sed -i '/^\[terra-mesa\]/,/^\[/ s/^enabled=.*/enabled=0/' "$f"; \
        fi; \
      done; \
    fi || true

COPY --from=artifact-builder /artifacts/ /

## make modifications desired in your image and install packages by modifying the build scripts.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/configure-image.sh

### LINTING
## Verify final image and contents are correct.
# RUN bootc container lint
