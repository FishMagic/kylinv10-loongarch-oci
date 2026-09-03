# syntax=docker/dockerfile:1.7
FROM scratch
ARG KYLIN_ROOTFS_SHA256=unknown
LABEL org.opencontainers.image.title="Galaxy Kylin V10 SP1 loongarch64 build environment" \
      org.opencontainers.image.description="Kylin V10 10.1 loongarch64 native BambuStudio build rootfs" \
      org.opencontainers.image.source="https://github.com/FishMagic/kylinv10-loongarch-oci" \
      com.fishmagic.kylin.suite="10.1" \
      com.fishmagic.kylin.architecture="loongarch64" \
      com.fishmagic.kylin.rootfs-sha256="$KYLIN_ROOTFS_SHA256"
ADD rootfs.tar /
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8
WORKDIR /work
ENTRYPOINT ["/bin/bash"]
