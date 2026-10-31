#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SingBoxTester"
BUNDLE_ID="io.github.sagernet.singbox.x25519mlkem768.tester"
MIN_SYSTEM_VERSION="14.0"
ARCH="arm64"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_PACKAGE_DIR="$ROOT_DIR/macos/SingBoxTester"
BUILD_DIR="$ROOT_DIR/build/macos-arm64"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
GO_BINARY="$BUILD_DIR/sing-box"
# Keep the test app focused on REALITY while retaining the Clash API used by
# the user's configuration for global/direct mode switching.
BUILD_TAGS="with_utls,with_clash_api"

stop_existing() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ -d "$APP_BUNDLE" ]]; then
    pkill -f "$APP_RESOURCES/sing-box" >/dev/null 2>&1 || true
  fi
}

build_sing_box() {
  mkdir -p "$BUILD_DIR"
  echo "Building sing-box for macOS $ARCH with tags: $BUILD_TAGS"
  (
    cd "$ROOT_DIR"
    env \
      GOOS=darwin \
      GOARCH="$ARCH" \
      CGO_ENABLED=1 \
      MACOSX_DEPLOYMENT_TARGET="$MIN_SYSTEM_VERSION" \
      GOCACHE="$BUILD_DIR/go-cache" \
      go build \
        -trimpath \
        -tags "$BUILD_TAGS" \
        -ldflags "$(tr -d '\r\n' < "$ROOT_DIR/release/LDFLAGS")" \
        -o "$GO_BINARY" \
        ./cmd/sing-box
  )
  if [[ "$(lipo -archs "$GO_BINARY")" != "$ARCH" ]]; then
    echo "Unexpected sing-box architecture: $(lipo -archs "$GO_BINARY")" >&2
    exit 1
  fi
}

build_swift_app() {
  echo "Building $APP_NAME SwiftUI app"
  swift build \
    --package-path "$SWIFT_PACKAGE_DIR" \
    --configuration release \
    --arch "$ARCH"
}

stage_app() {
  local swift_binary
  swift_binary="$(swift build \
    --package-path "$SWIFT_PACKAGE_DIR" \
    --configuration release \
    --arch "$ARCH" \
    --show-bin-path)/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$swift_binary" "$APP_BINARY"
  cp "$GO_BINARY" "$APP_RESOURCES/sing-box"
  chmod +x "$APP_BINARY" "$APP_RESOURCES/sing-box"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Sing-box REALITY 测试器</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.3</string>
  <key>CFBundleVersion</key>
  <string>4</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSArchitecturePriority</key>
  <array>
    <string>arm64</string>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

  codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE" >/dev/null
  echo "App bundle: $APP_BUNDLE"
}

build_all() {
  build_sing_box
  build_swift_app
  stage_app
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

stop_existing
build_all

case "$MODE" in
  run)
    open_app
    ;;
  --build|build)
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running"
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--verify]" >&2
    exit 2
    ;;
esac
