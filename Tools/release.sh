#!/bin/bash
#
# 배포용 빌드: Developer ID 서명 → 공증 → 스테이플 → DMG.
#
# 왜 이게 필요한가
#   ad-hoc 서명은 빌드할 때마다 서명이 바뀐다. 받는 사람은 Gatekeeper 경고를 뚫어야
#   하고, 업데이트할 때마다 손쉬운 사용 권한을 다시 줘야 한다. Developer ID 로
#   서명하고 공증하면 둘 다 사라진다 — 받아서 끌어다 놓으면 끝이다.
#
# 쓰는 법
#   make release VERSION=1.0
#   SKIP_NOTARIZE=1 make release      # 공증 없이 빌드만 (로컬 점검용)
#
# 미리 해둘 것 (한 번만)
#   1. Developer ID Application 인증서
#        Xcode › Settings › Accounts › 계정 선택 › Manage Certificates › + 
#   2. 공증 자격증명을 키체인에 저장
#        xcrun notarytool store-credentials CapsLockControl \
#          --apple-id <Apple ID> --team-id <팀 ID> --password <앱 암호>
#      앱 암호는 appleid.apple.com › 로그인 및 보안 › 앱 암호 에서 만든다.
#      계정 비밀번호가 아니다. 이 스크립트도 저장소도 암호를 담지 않는다.
set -euo pipefail

PROJ="CapsLockControl.xcodeproj"
SCHEME="CapsLockControl"
BUILD="${BUILD:-$PWD/build.noindex}"
DIST="$PWD/dist.noindex"
NOTARY_PROFILE="${NOTARY_PROFILE:-CapsLockControl}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

die() { printf '\n✘ %s\n' "$1" >&2; shift; for l in "$@"; do printf '  %s\n' "$l" >&2; done; exit 1; }
step() { printf '\n▸ %s\n' "$1"; }

# ── 버전 ──────────────────────────────────────────────────────────────────
VERSION="${VERSION:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PROJ/project.pbxproj" | head -1)
fi
# 같은 버전을 두 번 올려도 구분되도록 빌드 번호는 시각으로 박는다.
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

# ── 서명 인증서 ───────────────────────────────────────────────────────────
IDENTITY="${DEVELOPER_ID:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | grep "Developer ID Application" | head -1 \
        | sed -n 's/.*"\(.*\)".*/\1/p') || true
fi
[ -n "$IDENTITY" ] || die "Developer ID Application 인증서가 없습니다." \
    "" \
    "Xcode › Settings › Accounts › 계정 선택 › Manage Certificates" \
    "좌하단 + › Developer ID Application" \
    "" \
    "팀에서 Account Holder 또는 Admin 권한이 있어야 만들 수 있습니다." \
    "Apple Development 인증서로는 배포할 수 없습니다 — 그건 내 기기 전용입니다."

# "Developer ID Application: 이름 (TEAMID)" 에서 팀 ID 를 꺼낸다.
# 인증서 이름 형식이 다르면 TEAM_ID 환경변수로 직접 준다.
TEAM="${TEAM_ID:-$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')}"
[ -n "$TEAM" ] || die "인증서 이름에서 팀 ID 를 못 읽었습니다: $IDENTITY" \
    "TEAM_ID=<팀 ID> 로 직접 지정하세요."

# ── 공증 자격증명 ─────────────────────────────────────────────────────────
# 빌드에 몇 분 쓰고 나서야 자격증명이 없다고 알면 곤란하다. 먼저 본다.
if [ "$SKIP_NOTARIZE" != "1" ]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || die "공증 자격증명 '$NOTARY_PROFILE' 이 키체인에 없습니다." \
            "" \
            "xcrun notarytool store-credentials $NOTARY_PROFILE \\" \
            "  --apple-id <Apple ID> --team-id $TEAM --password <앱 암호>" \
            "" \
            "앱 암호: appleid.apple.com › 로그인 및 보안 › 앱 암호"
fi

printf 'CapsLock Control %s (build %s)\n' "$VERSION" "$BUILD_NUMBER"
printf '서명: %s\n' "$IDENTITY"
[ "$SKIP_NOTARIZE" = "1" ] && printf '공증: 건너뜀 (SKIP_NOTARIZE=1) — 배포용이 아닙니다\n'

APP="$BUILD/Build/Products/Release/CapsLockControl.app"
DMG="$DIST/CapsLockControl-$VERSION.dmg"
ZIP="$DIST/CapsLockControl-$VERSION.zip"
rm -rf "$DIST"; mkdir -p "$DIST"

# ── 1. 빌드 ───────────────────────────────────────────────────────────────
step "Release 빌드"
# --timestamp 없이 서명하면 인증서가 만료될 때 이미 배포된 앱까지 같이 죽는다.
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release \
    -derivedDataPath "$BUILD" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    KEYLAYER_CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM" \
    KEYLAYER_DEVELOPMENT_TEAM="$TEAM" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build | tail -5

step "서명 확인"
codesign --verify --strict --verbose=2 "$APP"

# 아래 검사는 전부 `case` 로 한다. `grep -q` 는 첫 매치에서 바로 끝나면서 앞
# 명령에 SIGPIPE 를 보내고, `set -o pipefail` 이 그걸 파이프라인 실패로 잡는다.
# 멀쩡한 빌드가 "하드닝 런타임 꺼짐" 으로 튕기는 사고가 이것 때문에 난다.
SIGNINFO=$(codesign -d --verbose=2 "$APP" 2>&1 || true)
case "$SIGNINFO" in
    *"flags="*"runtime"*) ;;
    *) die "하드닝 런타임이 꺼져 있습니다. 공증이 거부됩니다." ;;
esac

ENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - 2>/dev/null || true)
printf '%s\n' "$ENTS" | sed 's/^/  /'
# 공증에 몇 분 쓰고 나서 거부당하면 아깝다. 올리기 전에 끊는다.
case "$ENTS" in
    *get-task-allow*)
        die "com.apple.security.get-task-allow 가 붙어 있습니다. 공증이 거부됩니다." \
            "CODE_SIGN_INJECT_BASE_ENTITLEMENTS 가 Release 에서 NO 인지 확인하세요." ;;
esac
case "$ENTS" in
    *app-sandbox*)
        die "샌드박스가 켜져 있습니다. 샌드박스 안에서는 이벤트탭과 hidutil 이 죽습니다." ;;
esac

# ── 2. 앱 공증 ────────────────────────────────────────────────────────────
if [ "$SKIP_NOTARIZE" != "1" ]; then
    step "앱 공증 (몇 분 걸립니다)"
    # 공증 서비스는 .app 디렉터리를 직접 못 받는다. zip 으로 싸서 올린다.
    # ditto 의 --keepParent 가 있어야 .app 껍데기가 유지된다.
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

    step "앱에 티켓 붙이기"
    # 스테이플을 해야 오프라인에서도 Gatekeeper 가 바로 통과시킨다.
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
fi

# ── 3. DMG ────────────────────────────────────────────────────────────────
step "DMG 만들기"
STAGE="$DIST/stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
# /Applications 심볼릭 링크가 있어야 "끌어다 놓기" 가 된다.
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "CapsLock Control" -srcfolder "$STAGE" \
    -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$DMG"

# ── 4. DMG 공증 ───────────────────────────────────────────────────────────
if [ "$SKIP_NOTARIZE" != "1" ]; then
    step "DMG 공증"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"

    step "최종 확인"
    # 받는 사람의 Mac 이 실제로 보는 것과 같은 검사.
    spctl -a -t open --context context:primary-signature -vv "$DMG"
    xcrun stapler validate "$DMG"
fi

printf '\n완료: %s\n' "$DMG"
printf '크기: %s\n' "$(du -h "$DMG" | cut -f1)"
if [ "$SKIP_NOTARIZE" = "1" ]; then
    printf '\n⚠︎ 공증하지 않았습니다. 이 파일을 남에게 주면 Gatekeeper 가 막습니다.\n'
else
    printf '\n받는 사람은 DMG 를 열고 앱을 Applications 로 끌어다 놓으면 됩니다.\n'
    printf '경고창도, 우클릭 열기도 필요 없습니다.\n'
fi
