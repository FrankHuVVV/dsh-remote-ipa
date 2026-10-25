#!/usr/bin/env bash
# 一条命令出未签名 IPA（**必须在 macOS 上跑**）。
#
#   bash tools/build_ios.sh [版本号] [构建号]
#
# 例：bash tools/build_ios.sh 0.2.0 2
#
# 依次执行：pub get → analyze → test → flutter build ios --no-codesign → 打包 IPA + SHA-256。
# 产物在 app/DSHCompanion-<版本>-<构建号>-unsigned.ipa，下一步交给爱思助手签名
# （见 docs/RELEASE.md）。
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS 构建只能在 macOS 上做（当前系统：$(uname -s)）。" >&2
  echo "Windows / Linux 上请在 GitHub Actions 里跑 .github/workflows/ios-ipa.yml，" >&2
  echo "或把仓库放到 Mac 上执行本脚本。" >&2
  exit 1
fi

VERSION="${1:-0.2.0}"
BUILD_NUMBER="${2:-2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT/app"
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build ios \
  --release \
  --no-codesign \
  --build-name "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --dart-define=BUILD_COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo local)" \
  --dart-define=BUILD_TIME="$(date -u +%Y-%m-%dT%H:%MZ)" \
  --dart-define=APP_VERSION="$VERSION" \
  --dart-define=APP_BUILD_NUMBER="$BUILD_NUMBER"

cd "$ROOT"
bash tools/package_ipa.sh "$VERSION" "$BUILD_NUMBER"
