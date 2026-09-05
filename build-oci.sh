#!/usr/bin/env bash
# Export a generated Kylin rootfs as OCI and Docker-compatible archives.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ROOTFS_TAR="${1:-${KYLIN_ROOTFS_TAR:-$ROOT/rootfs.tar}}"
IMAGE="${2:-${KYLIN_IMAGE:-local/kylinv10-loongarch64:10.1}}"
OUT_DIR="${3:-${KYLIN_IMAGE_OUT:-$(dirname "$ROOTFS_TAR")}}"
OUTPUT_PREFIX="${OCI_OUTPUT_PREFIX:-kylinv10-loongarch64}"
DOCKERFILE="${OCI_DOCKERFILE:-$ROOT/Dockerfile}"

case "$(uname -m)" in
    loongarch64|loong64) ;;
    *)
        if [[ "${KYLIN_QEMU_TRANSLATED:-0}" != 1 ]]; then
            echo "native loongarch64 is required; found $(uname -m)" >&2
            exit 2
        fi
        ;;
esac
[ -f "$ROOTFS_TAR" ] || { echo "rootfs tar not found: $ROOTFS_TAR" >&2; exit 2; }
mkdir -p "$OUT_DIR"
CTX=$(mktemp -d)
trap 'rm -rf "$CTX"' EXIT
ln "$ROOTFS_TAR" "$CTX/rootfs.tar" 2>/dev/null || cp "$ROOTFS_TAR" "$CTX/rootfs.tar"
cp "$DOCKERFILE" "$CTX/Dockerfile"
ROOTFS_SHA=$(sha256sum "$ROOTFS_TAR" | cut -d' ' -f1)

# Export a real OCI archive for registry/import tooling.
docker buildx build \
    --platform linux/loong64 \
    --build-arg KYLIN_ROOTFS_SHA256="$ROOTFS_SHA" \
    --output "type=oci,dest=$OUT_DIR/$OUTPUT_PREFIX.oci.tar" \
    "$CTX"

# Also load a local image for immediate native smoke tests and CI caches.
docker import --platform linux/loong64 \
    --change 'ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
    --change 'WORKDIR /work' \
    --change 'ENTRYPOINT ["/bin/bash"]' \
    "$ROOTFS_TAR" "$IMAGE"
ARCH=$(docker image inspect "$IMAGE" --format '{{.Architecture}}')
[ "$ARCH" = loong64 ] || { echo "wrong image architecture: $ARCH" >&2; exit 1; }
docker save "$IMAGE" -o "$OUT_DIR/${OUTPUT_PREFIX}-image.tar"
if command -v zstd >/dev/null 2>&1; then
    zstd -T0 -19 -f "$OUT_DIR/$OUTPUT_PREFIX.oci.tar" -o "$OUT_DIR/$OUTPUT_PREFIX.oci.tar.zst"
    zstd -T0 -19 -f "$OUT_DIR/${OUTPUT_PREFIX}-image.tar" -o "$OUT_DIR/${OUTPUT_PREFIX}-image.tar.zst"
fi
printf 'loongarch64 image exported: %s\n' "$IMAGE"
