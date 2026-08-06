#!/bin/bash
# 统一构建脚本：每个 App 在 /Users/Witten/Downloads/Temp/ 下建立自己名字的文件夹，
# 全部构建产物统一落在 <App名> 文件夹内，不再写入项目目录（如 build/、Vendor/SwiftMath/build）。
# 约定：Downloads/Temp/<App名> 即该 App 的暂存目录（构建、中间件、临时文件均放这里）。
# 用法：
#   ./Scripts/build.sh                 # macOS Debug
#   ./Scripts/build.sh ios            # iOS Debug
#   ./Scripts/build.sh clean          # 清理该 App 的暂存目录
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="/Users/Witten/Downloads/Temp/ATeaching"

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
