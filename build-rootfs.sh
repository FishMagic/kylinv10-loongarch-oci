#!/usr/bin/env bash
# Assemble a runnable Galaxy Kylin V10 SP1 10.1 loongarch64 rootfs.
# The helper image is Debian-ports only for bootstrap tooling; every package
# installed into the output is resolved from the checked-in Kylin archive.
set -euo pipefail

SOURCE_FILE="${KYLIN_APT_SOURCES_FILE:-/src/kylin.sources}"
PACKAGES_FILE="${KYLIN_PACKAGES_FILE:-/src/packages-kylinv10-loongarch64.txt}"
OUT_DIR="${KYLIN_ROOTFS_OUT:-/out}"
ROOTFS="${KYLIN_ROOTFS_DIR:-/var/tmp/kylinv10-loongarch64-rootfs}"

[ -s "$SOURCE_FILE" ] || { echo "missing Kylin source file: $SOURCE_FILE" >&2; exit 2; }
[ -s "$PACKAGES_FILE" ] || { echo "missing Kylin package list: $PACKAGES_FILE" >&2; exit 2; }
case "$(dpkg --print-architecture)" in
    loong64|loongarch64) ;;
    *) echo "loongarch64 helper required; found $(dpkg --print-architecture)" >&2; exit 2 ;;
esac

SOURCE_LINE=$(awk '$1 == "deb" { print; exit }' "$SOURCE_FILE")
[ -n "$SOURCE_LINE" ] || { echo "Kylin source file has no deb entry" >&2; exit 2; }
SOURCE_BODY=$(sed -E 's/^deb[[:space:]]+\[[^]]+\][[:space:]]+//' <<<"$SOURCE_LINE")
read -r REPOSITORY_URL SUITE COMPONENTS_REST <<<"$SOURCE_BODY"
COMPONENTS="${COMPONENTS_REST// /,}"
[ -n "$REPOSITORY_URL" ] && [ -n "$SUITE" ] && [ -n "$COMPONENTS" ] || {
    echo "malformed Kylin source line: $SOURCE_LINE" >&2
    exit 2
}

mapfile -t PACKAGES < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$PACKAGES_FILE")
[ "${#PACKAGES[@]}" -gt 0 ] || { echo "Kylin package list is empty" >&2; exit 2; }
INCLUDE=$(IFS=,; echo "${PACKAGES[*]}")

rm -rf "$ROOTFS"
mkdir -p "$OUT_DIR" "$ROOTFS"
rm -f /etc/apt/sources.list
rm -rf /etc/apt/sources.list.d
mkdir -p /etc/apt/sources.list.d
printf '%s\n' "$SOURCE_LINE" > /etc/apt/sources.list
cat > /etc/apt/apt.conf.d/99-kylin-bootstrap <<'APT'
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
APT
export DEBIAN_FRONTEND=noninteractive
apt-get update \
    -o Acquire::AllowInsecureRepositories=true \
    -o APT::Get::AllowUnauthenticated=true

# Debian debootstrap has no built-in 10.1 profile; the helper image aliases
# its sid package recipe to 10.1 while retaining the Kylin suite and URL.
printf 'Bootstrapping Kylin %s (%s), %s packages\n' "$SUITE" "$REPOSITORY_URL" "${#PACKAGES[@]}"
debootstrap \
    --no-check-gpg \
    --arch=loongarch64 \
    --variant=minbase \
    --components="$COMPONENTS" \
    --include="$INCLUDE" \
    "$SUITE" "$ROOTFS" "$REPOSITORY_URL"

# Keep the exact source available for diagnostics, without copying helper apt
# credentials or the helper's package indexes into the image.
rm -rf "$ROOTFS/var/lib/apt/lists" "$ROOTFS/var/cache/apt/archives"
mkdir -p "$ROOTFS/var/lib/apt/lists" "$ROOTFS/var/cache/apt/archives" "$ROOTFS/etc/apt/sources.list.d"
printf '%s\n' "$SOURCE_LINE" > "$ROOTFS/etc/apt/sources.list"
cat > "$ROOTFS/etc/apt/apt.conf.d/99-kylin-build" <<'APT'
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
APT
cat > "$ROOTFS/etc/kylinv10-build-environment" <<META
NAME=Galaxy Kylin V10 SP1
SUITE=$SUITE
ARCHITECTURE=loongarch64
REPOSITORY_URL=$REPOSITORY_URL
COMPONENTS=${COMPONENTS//,/ }
META

# A build-only image must not attempt to start services during future package
# operations, but it still needs a valid policy file for apt diagnostics.
mkdir -p "$ROOTFS/usr/sbin"
cat > "$ROOTFS/usr/sbin/policy-rc.d" <<'POLICY'
#!/bin/sh
exit 101
POLICY
chmod 0755 "$ROOTFS/usr/sbin/policy-rc.d"

for required in \
    "$ROOTFS/bin/bash" \
    "$ROOTFS/usr/bin/cmake" \
    "$ROOTFS/usr/bin/ninja" \
    "$ROOTFS/usr/bin/g++" \
    "$ROOTFS/usr/bin/git" \
    "$ROOTFS/usr/bin/wget" \
    "$ROOTFS/usr/include/webkitgtk-4.0/webkit2/webkit2.h"; do
    [ -e "$required" ] || { echo "Kylin rootfs missing required file: $required" >&2; exit 1; }
done
WEBKIT_PC=$(find "$ROOTFS/usr/lib" -type f -name 'webkit2gtk-4.0.pc' -print -quit)
[ -n "$WEBKIT_PC" ] || { echo "Kylin rootfs missing webkit2gtk-4.0.pc" >&2; exit 1; }

{
    printf 'NAME=Galaxy Kylin V10 SP1\n'
    printf 'SUITE=%s\n' "$SUITE"
    printf 'ARCHITECTURE=loongarch64\n'
    printf 'REPOSITORY_URL=%s\n' "$REPOSITORY_URL"
    printf 'COMPONENTS=%s\n' "${COMPONENTS//,/ }"
    printf 'PACKAGE_COUNT=%s\n' "${#PACKAGES[@]}"
    printf 'WEBKIT_PKGCONFIG=%s\n' "${WEBKIT_PC#$ROOTFS}"
} > "$OUT_DIR/kylinv10-loongarch64-manifest.txt"

tar --numeric-owner --owner=0 --group=0 --sort=name \
    --mtime='UTC 1970-01-01' -C "$ROOTFS" -cf "$OUT_DIR/rootfs.tar" .
sha256sum "$OUT_DIR/rootfs.tar" > "$OUT_DIR/rootfs.tar.sha256"
printf 'Kylin V10 loongarch64 rootfs ready: %s\n' "$OUT_DIR/rootfs.tar"
