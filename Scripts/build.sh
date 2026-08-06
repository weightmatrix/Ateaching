#!/bin/bash
# 统一构建脚本：所有构建产物统一落在 ~/Library/Developer/Xcode/DerivedData/ATeaching，
# 不再写入项目目录内的 build/ 或 Vendor/SwiftMath/build。
# 用法：
#   ./Scripts/build.sh                 # macOS Debug
#   ./Scripts/build.sh ios             # iOS Debug
#   ./Scripts/build.sh clean           # 清理统一构建目录
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/ATeaching"

cd "$PROJECT_DIR"

if [[ "${1:-}" == "clean" ]]; then
    echo "清理统一构建目录: $DERIVED_DATA"
    rm -rf "$DERIVED_DATA"
    exit 0
fi

DESTINATION="generic/platform=macOS"
if [[ "${1:-}" == "ios" ]]; then
    DESTINATION="generic/platform=iOS"
fi

echo "构建位置: $DERIVED_DATA"
xcodebuild build \
    -project ATeaching.xcodeproj \
    -scheme ATeaching \
    -configuration Debug \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA"
