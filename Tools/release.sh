#!/bin/bash
#
# 릴리스: 버전 올리기 → Developer ID 서명 → 공증 → 스테이플 → DMG·업데이트 zip
#         → 태그·푸시 → GitHub 릴리스에 올리기. 명령 하나로 끝난다.
#
# 왜 이게 필요한가
#   ad-hoc 서명은 빌드할 때마다 서명이 바뀐다. 받는 사람은 Gatekeeper 경고를 뚫어야
#   하고, 업데이트할 때마다 손쉬운 사용 권한을 다시 줘야 한다. Developer ID 로
#   서명하고 공증하면 둘 다 사라진다 — 받아서 끌어다 놓으면 끝이다.
#   GitHub 릴리스에 올리면 이미 깐 앱은 새 버전을 알아서 찾아 업데이트를 권한다
#   (UpdateCheck.swift 가 RELEASE_REPO 의 최신 릴리스를 본다).
#
# 쓰는 법
#   make release VERSION=0.2.0
#   RELEASE_NOTES_FILE=notes.md make release VERSION=0.2.0   # 릴리스 설명을 직접 쓸 때
#   SKIP_NOTARIZE=1 make release      # 공증·업로드 없이 빌드만 (로컬 점검용)
#
#   릴리스 설명을 주지 않으면 지난 태그 뒤의 커밋 제목으로 만든다.
#
# 미리 해둘 것 (한 번만)
#   1. Developer ID Application 인증서
#        Xcode › Settings › Accounts › 계정 선택 › Manage Certificates › +
#   2. 공증 자격증명을 키체인에 저장
#        xcrun notarytool store-credentials CapsLockControl \
#          --apple-id <Apple ID> --team-id <팀 ID> --password <앱 암호>
#      앱 암호는 appleid.apple.com › 로그인 및 보안 › 앱 암호 에서 만든다.
#      계정 비밀번호가 아니다. 이 스크립트도 저장소도 암호를 담지 않는다.
#      다른 이름으로 저장했으면 Config/Release.local.env 에 NOTARY_PROFILE=<이름> 을 적는다.
#   3. gh 로그인 (gh auth login) — 릴리스 저장소 주인 계정으로
set -euo pipefail

PROJ="CapsLockControl.xcodeproj"
SCHEME="CapsLockControl"
BUILD="${BUILD:-$PWD/build.noindex}"
DIST="$PWD/dist.noindex"

# 이 맥에만 맞는 값(공증 프로필 이름 등). 저장소에 올리지 않는다(.gitignore).
if [ -f Config/Release.local.env ]; then
    # shellcheck disable=SC1091
    . Config/Release.local.env
fi
NOTARY_PROFILE="${NOTARY_PROFILE:-CapsLockControl}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
# UpdateCheck.Feed.github 와 같은 저장소여야 깔린 앱이 새 버전을 찾는다.
RELEASE_REPO="${RELEASE_REPO:-itaehyeok/capslock-control}"
RELEASE_BRANCH="${RELEASE_BRANCH:-main}"

die() { printf '\n✘ %s\n' "$1" >&2; shift; for l in "$@"; do printf '  %s\n' "$l" >&2; done; exit 1; }
step() { printf '\n▸ %s\n' "$1"; }

# ── 버전 ──────────────────────────────────────────────────────────────────
VERSION="${VERSION:-}"
PUBLISH=1
[ "$SKIP_NOTARIZE" = "1" ] && PUBLISH=0
if [ -z "$VERSION" ]; then
    [ "$PUBLISH" = "1" ] && die "올릴 버전을 주세요." "make release VERSION=0.2.0"
    VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PROJ/project.pbxproj" | head -1)
fi
# 앱은 숫자 셋인 태그만 새 버전으로 알아본다(UpdateCheck.parse).
if [ "$PUBLISH" = "1" ] && ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    die "버전은 0.2.0 처럼 숫자 셋이어야 합니다: $VERSION"
fi
TAG="v$VERSION"
# 같은 버전을 두 번 올려도 구분되도록 빌드 번호는 시각으로 박는다.
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

# ── 올리기 전 확인 ────────────────────────────────────────────────────────
# 빌드·공증에 몇 분 쓰고 나서야 못 올린다는 걸 알면 곤란하다. 올릴 수 있는지부터 본다.
if [ "$PUBLISH" = "1" ]; then
    command -v gh >/dev/null || die "gh 가 없습니다." "brew install gh && gh auth login"
    [ "$(git rev-parse --abbrev-ref HEAD)" = "$RELEASE_BRANCH" ] \
        || die "$RELEASE_BRANCH 브랜치에서만 올립니다. 지금: $(git rev-parse --abbrev-ref HEAD)"
    [ -z "$(git status --porcelain)" ] || die "커밋 안 된 변경이 있습니다. 커밋하거나 치운 뒤 다시 하세요." \
        "" "$(git status --short | head -10)"
    git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "태그 $TAG 가 이미 있습니다. 버전을 올려 주세요."

    # 지난 릴리스보다 커야 깔린 앱이 새 버전으로 알아본다.
    # 태그가 하나도 없으면 grep 이 1 로 끝난다. 첫 릴리스라 괜찮다.
    LAST_TAG=$(git tag -l 'v*' | sed 's/^v//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)
    if [ -n "$LAST_TAG" ]; then
        NEWEST=$(printf '%s\n%s\n' "$LAST_TAG" "$VERSION" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
        { [ "$NEWEST" = "$VERSION" ] && [ "$LAST_TAG" != "$VERSION" ]; } \
            || die "버전 $VERSION 이 지난 릴리스 v$LAST_TAG 보다 크지 않습니다."
    fi

    # 개인 저장소를 여러 gh 계정 중 하나로 올릴 수 있으니 저장소 주인 계정의 토큰을 쓴다.
    OWNER="${RELEASE_REPO%%/*}"
    if [ -z "${GH_TOKEN:-}" ]; then
        GH_TOKEN="$(gh auth token --hostname github.com --user "$OWNER" 2>/dev/null || true)"
        export GH_TOKEN
    fi
    VISIBILITY=$(gh repo view "$RELEASE_REPO" --json visibility -q .visibility 2>/dev/null) \
        || die "$RELEASE_REPO 저장소에 접근하지 못했습니다." "gh auth login 으로 $OWNER 계정에 로그인하세요."
    # 비공개 저장소의 릴리스는 로그인 없이 못 받는다. 깔린 앱이 새 버전을 찾지 못한다.
    [ "$VISIBILITY" = "PUBLIC" ] || die "$RELEASE_REPO 가 공개 저장소가 아닙니다($VISIBILITY)." \
        "앱의 업데이트 확인은 로그인 없이 묻습니다. 공개로 바꾼 뒤 다시 하세요."
fi

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
if [ "$SKIP_NOTARIZE" != "1" ]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || die "공증 자격증명 '$NOTARY_PROFILE' 이 키체인에 없습니다." \
            "" \
            "xcrun notarytool store-credentials $NOTARY_PROFILE \\" \
            "  --apple-id <Apple ID> --team-id $TEAM --password <앱 암호>" \
            "" \
            "앱 암호: appleid.apple.com › 로그인 및 보안 › 앱 암호" \
            "다른 이름으로 저장해 뒀다면 Config/Release.local.env 에 NOTARY_PROFILE=<이름>"
fi

printf 'CapsLock Control %s (build %s)\n' "$VERSION" "$BUILD_NUMBER"
printf '서명: %s\n' "$IDENTITY"
[ "$SKIP_NOTARIZE" = "1" ] && printf '공증·업로드: 건너뜀 (SKIP_NOTARIZE=1) — 배포용이 아닙니다\n'

# ── 0. 버전 올리기 ────────────────────────────────────────────────────────
# 저장소의 버전도 같이 올려 둔다. 개발 빌드가 지난 버전을 달고 있으면 앱이 방금 올린
# 릴리스를 "새 버전" 으로 권한다. 중간에 실패해서 다시 돌려도 두 번 커밋하지 않는다.
if [ "$PUBLISH" = "1" ]; then
    step "버전을 $VERSION 으로"
    sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/" "$PROJ/project.pbxproj"
    if git diff --quiet -- "$PROJ/project.pbxproj"; then
        printf '  이미 %s 입니다\n' "$VERSION"
    else
        git commit -q -m "chore(release): $TAG" -- "$PROJ/project.pbxproj"
        printf '  커밋: %s\n' "$(git log -1 --format='%h %s')"
    fi
fi

APP="$BUILD/Build/Products/Release/CapsLockControl.app"
DMG="$DIST/CapsLockControl-$VERSION.dmg"
# 업데이트용 zip. 이름은 UpdateCheck.assetName 과 같아야 한다.
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
# 깔린 앱은 같은 팀이 서명한 업데이트만 받는다(AppUpdater). 팀이 바뀌면 업데이트가 끊긴다.
case "$SIGNINFO" in
    *"TeamIdentifier=$TEAM"*) ;;
    *) die "서명 팀이 $TEAM 이 아닙니다." ;;
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
# `notarytool submit --wait` 는 애플이 거절(Invalid)해도 성공으로 끝난다.
# 그래서 결과 JSON 의 status 를 직접 본다.
notarize() {
    local file="$1" result status id
    result=$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" \
        --wait --output-format json)
    status=$(printf '%s' "$result" | plutil -extract status raw -o - - 2>/dev/null || true)
    if [ "$status" != "Accepted" ]; then
        id=$(printf '%s' "$result" | plutil -extract id raw -o - - 2>/dev/null || true)
        die "공증이 거부됐습니다 ($status)." \
            "xcrun notarytool log $id --keychain-profile $NOTARY_PROFILE"
    fi
}

if [ "$SKIP_NOTARIZE" != "1" ]; then
    step "앱 공증 (몇 분 걸립니다)"
    # 공증 서비스는 .app 디렉터리를 직접 못 받는다. zip 으로 싸서 올린다.
    # ditto 의 --keepParent 가 있어야 .app 껍데기가 유지된다.
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"

    step "앱에 티켓 붙이기"
    # 스테이플을 해야 오프라인에서도 Gatekeeper 가 바로 통과시킨다.
    xcrun stapler staple "$APP"
fi

# 티켓을 붙인 앱으로 업데이트용 zip 을 다시 싼다. `zip` 은 심볼릭 링크와 확장
# 속성을 잃어 서명이 깨진다. ditto 를 쓴다.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

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
    notarize "$DMG"
    xcrun stapler staple "$DMG"

    step "최종 확인"
    # 받는 사람의 Mac 이 실제로 보는 것과 같은 검사.
    spctl -a -t open --context context:primary-signature -vv "$DMG"
    xcrun stapler validate "$DMG"
fi

if [ "$PUBLISH" != "1" ]; then
    printf '\n완료: %s\n' "$DMG"
    printf '크기: %s\n' "$(du -h "$DMG" | cut -f1)"
    printf '\n⚠︎ 공증하지 않았습니다. 이 파일을 남에게 주면 Gatekeeper 가 막습니다.\n'
    exit 0
fi

# ── 5. 태그·푸시 ──────────────────────────────────────────────────────────
step "태그 $TAG 와 커밋 올리기"
git tag "$TAG"
if ! git push -q origin "HEAD:$RELEASE_BRANCH" || ! git push -q origin "$TAG"; then
    git tag -d "$TAG" >/dev/null
    git push -q origin ":refs/tags/$TAG" 2>/dev/null || true
    die "푸시하지 못했습니다. 릴리스는 올리지 않았습니다." \
        "원격과 갈라졌는지 확인한 뒤 같은 명령을 다시 돌리세요."
fi

# ── 6. GitHub 릴리스 ──────────────────────────────────────────────────────
step "GitHub 릴리스 올리기"
NOTES="$DIST/notes.md"
if [ -n "${RELEASE_NOTES_FILE:-}" ]; then
    cp "$RELEASE_NOTES_FILE" "$NOTES"
else
    {
        if [ -n "${LAST_TAG:-}" ]; then
            printf '## 바뀐 점\n\n'
            git log --format='- %s' "v$LAST_TAG..$TAG" | grep -v 'chore(release)' || true
        else
            printf '첫 공개 버전입니다.\n'
        fi
        printf '\n## 설치\n\n'
        printf 'CapsLockControl-%s.dmg 를 열고 앱을 응용 프로그램 폴더로 끌어다 놓으세요.\n' "$VERSION"
        printf '이미 쓰고 있다면 앱이 새 버전을 알아서 알려 줍니다(메뉴바 › 새 버전 설치).\n'
    } > "$NOTES"
fi
gh release create "$TAG" "$ZIP" "$DMG" -R "$RELEASE_REPO" --verify-tag \
    --title "CapsLock Control $TAG" --notes-file "$NOTES"

printf '\n완료: https://github.com/%s/releases/tag/%s\n' "$RELEASE_REPO" "$TAG"
printf '깔린 앱은 몇 시간 안에(창을 열면 바로) 새 버전을 알려 줍니다.\n'
