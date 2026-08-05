#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "用法: bash Scripts/install_swiftmath_offline.sh <SwiftMath-offline.tgz|zip>"
  exit 1
fi

ARCHIVE_PATH="$1"
if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "文件不存在: $ARCHIVE_PATH"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
TARGET_DIR="$VENDOR_DIR/SwiftMath"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$VENDOR_DIR"

case "$ARCHIVE_PATH" in
  *.tgz|*.tar.gz)
    tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"
    ;;
  *.zip)
    unzip -q "$ARCHIVE_PATH" -d "$TMP_DIR"
    ;;
  *)
    echo "仅支持 .tgz/.tar.gz/.zip"
    exit 1
    ;;
esac

# 兼容 archive 里最外层目录名不同
SWIFTMATH_SRC="$(find "$TMP_DIR" -maxdepth 3 -type f -name 'Package.swift' -print | head -n 1 | xargs -I{} dirname "{}")"
if [[ -z "${SWIFTMATH_SRC:-}" ]]; then
  echo "未找到 SwiftMath Package.swift，安装失败。"
  exit 1
fi

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
cp -R "$SWIFTMATH_SRC"/. "$TARGET_DIR"/

DATE_STR="$(date '+%Y-%m-%d %H:%M:%S')"
{
  echo "installed_at=$DATE_STR"
  echo "source_archive=$(basename "$ARCHIVE_PATH")"
} > "$VENDOR_DIR/SWIFTMATH_VERSION.txt"

echo "✅ 已内置 SwiftMath 到: $TARGET_DIR"
echo "下一步：Xcode -> File -> Add Package Dependencies -> Add Local... -> 选择 Vendor/SwiftMath"
