#!/usr/bin/env bash
# 把 `flutter build ios --no-codesign` 的产物打成未签名 IPA。
#
# 用法（macOS，仓库根目录）：
#   bash tools/package_ipa.sh 1.0.0 1 [app/build/ios/iphoneos/Runner.app]
#
# 产物：app/DSHCompanion-<version>-<build>-unsigned.ipa 与同名 .sha256
# 之后交给爱思助手签名（见 docs/RELEASE.md）。
set -euo pipefail

VERSION="${1:-1.0.0}"
BUILD_NUMBER="${2:-1}"
APP_PATH="${3:-app/build/ios/iphoneos/Runner.app}"
OUT_DIR="app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "找不到 $APP_PATH" >&2
  echo "先跑：cd app && flutter build ios --release --no-codesign" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/"

IPA="$OUT_DIR/DSHCompanion-${VERSION}-${BUILD_NUMBER}-unsigned.ipa"
rm -f "$IPA" "$IPA.sha256"

( cd "$WORK_DIR" && zip -qry "$OLDPWD/$IPA" Payload )

( cd "$OUT_DIR" && shasum -a 256 "$(basename "$IPA")" | tee "$(basename "$IPA").sha256" )

echo "OK: $IPA"
echo "签名：爱思助手 → 工具箱 → IPA 签名（见 docs/RELEASE.md）"
