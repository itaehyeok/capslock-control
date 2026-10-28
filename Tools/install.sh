#!/bin/bash
#
# 빌드해서 /Applications 에 깔고 실행한다 (make install).
#
# 왜 서명을 고르는가
#   손쉬운 사용 권한은 앱의 코드 서명에 묶인다. 공개 릴리스(Developer ID 서명)를 깔고
#   권한을 준 Mac 에 개발 서명(ad-hoc·Apple Development) 빌드를 덮으면, 목록에는
#   켜져 있는데 macOS 가 이 앱을 다른 앱으로 본다. 엔진이 켜지지 않아 단축키가 전부 죽는다.
#
#   - Config/Release.local.env 에 DEVELOPER_ID 가 있으면 그 인증서로 서명한 Release 를 깐다.
#     공개 릴리스와 같은 서명이라 권한이 그대로 이어진다. 공증은 하지 않는다(이 Mac 에서만 쓴다).
#   - 없으면 예전처럼 Debug 를 깐다(Config/Signing.xcconfig 의 서명).
#     이때 이미 깔린 앱이 Developer ID 서명이면 멈춘다. 그래도 덮으려면 FORCE=1.
set -euo pipefail

PROJ="CapsLockControl.xcodeproj"
SCHEME="CapsLockControl"
BUILD="${BUILD:-$PWD/build.noindex}"
DEST="/Applications/CapsLockControl.app"

# 이 맥에만 맞는 값. 저장소에 올리지 않는다(.gitignore).
if [ -f Config/Release.local.env ]; then
    # shellcheck disable=SC1091
    . Config/Release.local.env
fi
DEVELOPER_ID="${DEVELOPER_ID:-}"
FORCE="${FORCE:-0}"

die() { printf '\n✘ %s\n' "$1" >&2; shift; for l in "$@"; do printf '  %s\n' "$l" >&2; done; exit 1; }

if [ -n "$DEVELOPER_ID" ]; then
    # "Developer ID Application: 이름 (TEAMID)" 에서 팀 ID 를 꺼낸다.
    TEAM="${TEAM_ID:-$(printf '%s' "$DEVELOPER_ID" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')}"
    [ -n "$TEAM" ] || die "인증서 이름에서 팀 ID 를 못 읽었습니다: $DEVELOPER_ID" \
        "Config/Release.local.env 에 TEAM_ID=<팀 ID> 를 함께 적으세요."
    printf '서명: %s (Release)\n' "$DEVELOPER_ID"
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release \
        -derivedDataPath "$BUILD" \
        CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
        KEYLAYER_CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
        DEVELOPMENT_TEAM="$TEAM" \
        KEYLAYER_DEVELOPMENT_TEAM="$TEAM" \
        build | tail -3
    APP="$BUILD/Build/Products/Release/CapsLockControl.app"
else
    # grep -q 대신 case 로 본다. pipefail 아래에서 grep -q 는 SIGPIPE 로 실패할 수 있다.
    INSTALLED=$(codesign -dvv "$DEST" 2>&1 || true)
    case "$INSTALLED" in
        *"Authority=Developer ID Application"*)
            [ "$FORCE" = "1" ] || die "깔려 있는 앱이 Developer ID 로 서명돼 있습니다." \
                "개발 서명 빌드로 덮으면 손쉬운 사용 권한이 맞지 않아 단축키가 전부 멈춥니다." \
                "" \
                "같은 인증서로 깔려면 Config/Release.local.env 에 적고 다시 make install:" \
                "  DEVELOPER_ID=\"Developer ID Application: 이름 (팀ID)\"" \
                "" \
                "그래도 개발 빌드로 덮으려면 FORCE=1 make install" \
                "(그 뒤 손쉬운 사용 목록에서 지우고 다시 켜야 합니다)" ;;
    esac
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug \
        -derivedDataPath "$BUILD" build | tail -3
    APP="$BUILD/Build/Products/Debug/CapsLockControl.app"
fi

codesign --verify --strict "$APP" || die "서명 검사에 실패했습니다: $APP"

pkill -x CapsLockControl 2>/dev/null || true
sleep 0.5
rm -rf "$DEST"
cp -R "$APP" /Applications/
echo "설치 완료: $DEST"
codesign -dvv "$DEST" 2>&1 | grep -E '^(Authority=(Developer ID Application|Apple Development)|TeamIdentifier=)' \
    | sed 's/^/  /' || true
open "$DEST"
