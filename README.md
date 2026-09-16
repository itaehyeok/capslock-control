# CapsLockControl

Karabiner-Elements 와 Raycast 의 "실제로 쓰는 기능"만 대체하는 macOS 메뉴바 유틸리티.
Karabiner 클론도, Raycast 클론도 아니다. 외부 의존성 없이 Apple framework 만 쓴다.

## 핵심 특징

**키보드**

- **Caps Lock 과 Right Option 을 각각 독립된 레이어 키로** 쓴다.
  `Caps + C` 와 `Right Option + C` 는 완전히 다른 단축키다.
- **Caps Lock 을 혼자 짧게 치면 원래 대문자 고정**이 동작한다.
  조합해서 쓰면 레이어, 톡 치면 Caps Lock.
- **Right Command → F18** 로 한/영을 전환한다 (macOS 입력 소스 단축키를 그대로 쓴다).
- **fn ↔ 왼쪽 Control 맞바꾸기** (옵션).
- 등록하지 않은 키는 삼켜서 **엉뚱한 글자가 입력되지 않는다**. 정책은 설정으로 바꾼다.

**단축키로 할 수 있는 일**

- **앱 실행/전환** — 실행 중이면 앞으로, 아니면 실행.
- **같은 키를 다시 누르면 토글** — 숨기거나 직전 앱으로 돌아간다. 키마다 따로 정할 수 있다.
- **미디어 제어** — 재생/일시정지·다음·이전. 지금 재생 중인 앱이 받는다.
- **다른 앱의 전역 단축키 호출** — `⌃⌥⇧A` 같은 조합을 대신 눌러 준다.
  Caps Lock 은 모디파이어가 아니라서 다른 앱이 직접 등록할 수 없는데, 이걸로 우회한다.

**편집**

- **실제 맥북 모양의 키보드 에디터.** 빈 키를 누르면 앱 피커가 열리고,
  키캡을 끌어서 다른 키로 옮길 수 있다(양쪽이 맞바뀐다).
- 앱 피커는 **실행 중인 앱 + 설치된 앱**을 한 글자 칠 때마다 걸러 준다.
  경로나 bundle ID 를 입력할 일이 없다.
- 설치되지 않은 앱은 **Missing** 으로 표시된다.
- `전체 키보드` / `단축키 키만` 두 배치를 전환할 수 있다.

**설정과 동기화**

- 설정은 사람이 읽고 고칠 수 있는 **JSON** 이다. 직접 고치면 **재시작 없이 바로 반영**된다.
- 저장은 atomic. 파일이 깨져 있으면 지우지 않고 백업한 뒤 기본값으로 시작한다.
- **GitHub 로 Mac 사이 동기화** — Export 는 시각과 Mac 이름이 붙은 새 스냅샷을 쌓고
  (기존 것을 지우지 않는다), Import 는 그중 하나를 골라 **항목별로 체크해서** 가져온다.
  가져오기 전에 로컬 백업이 항상 남는다.
- 토큰·키를 저장하지 않고 이 Mac 에 이미 설정된 SSH 인증을 쓴다.

**동작 방식**

- Dock 아이콘 없는 **메뉴바 전용 앱**. 로그인 시 자동 실행(SMAppService).
- 가상 HID 드라이버를 만들지 않는다. Apple 이 제공하는 `hidutil` 리맵 +
  얇은 `CGEventTap` 조합이다.
- **앱을 종료하면 키보드가 원래대로 돌아간다.** ⌘Q 든 강제 종료(SIGTERM)든.

## 처음 쓰는 사람

### 1. 받아서 설치

**Xcode 26 이상이 필요하다.** Command Line Tools 만으로는 안 된다.

```bash
git clone https://github.com/itaehyeok/capslock-control.git
cd capslock-control
make install
```

`make install` 이 빌드해서 `/Applications` 에 넣고 실행까지 한다.
Apple 개발자 계정이 없어도 된다(ad-hoc 서명).

> 계정이 있으면 `Config/Signing.local.xcconfig.example` 를
> `Signing.local.xcconfig` 로 복사해 팀 ID 를 넣자. 서명이 고정되어
> **손쉬운 사용 권한을 다시 묻지 않는다.** ad-hoc 은 빌드할 때마다 서명이 달라져서
> 권한을 다시 물어볼 수 있다.

### 2. 권한 허용

첫 실행이면 창이 뜨고 손쉬운 사용 권한을 요청한다.
**시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용** 에서 CapsLock Control 을 켠다.

허용했는데 단축키가 안 먹으면 **앱을 한 번 껐다 켜자**. macOS 가 권한을 반영하는
데 재실행이 필요한 경우가 있다.

### 3. Karabiner 를 쓰고 있다면

같은 키를 두 도구가 가로채므로 겹친다. 지울 필요는 없고 **빈 프로필**로 바꾸면 된다.

> Karabiner-Elements 설정 › Profiles › Add profile › 새 프로필 선택

되돌리는 것도 클릭 한 번이다. CapsLock Control 은 다른 앱을 절대 자동 종료하지 않고
경고만 띄운다.

### 4. 단축키 만들기

**단축키는 비어 있는 상태로 시작한다.** 키보드 그림에서 빈 키를 누르면 앱 피커가
열린다. 목록에서 고르기만 하면 된다.

### 5. 한/영 전환을 쓰려면 (선택)

이것만 macOS 설정에서 직접 해야 한다.

> 시스템 설정 › 키보드 › 키보드 단축키 › 입력 소스 →
> **"이전 입력 소스 선택"** 에 **F18** 지정

그러면 오른쪽 ⌘ 로 한/영이 전환된다. 이 설정을 안 하면 오른쪽 ⌘ 만 없어지고
아무 일도 일어나지 않는다. 오른쪽 ⌘ 를 그냥 쓰고 싶으면
설정 › 키보드 › Right Command 를 `그대로 두기` 로 바꾼다.

---

### 알아 두면 좋은 것

**이 앱은 세 키를 가져간다** — Caps Lock, Right Option, Right Command.
Right Command 는 설정에서 끌 수 있지만 앞의 둘은 레이어 키라 고정이다.
**Caps Lock 은 혼자 짧게 치면 원래 대문자 고정으로 동작**하니 완전히 잃는 건 아니다.

**Dock 아이콘이 없다.** 메뉴바의 키보드 아이콘을 클릭하면 메뉴가 나온다.
메뉴바가 꽉 차서 아이콘이 안 보이면, Finder 에서 `/Applications/CapsLockControl.app`
을 더블클릭하면 창이 열린다. 창 오른쪽 위 ⚙️ 로 설정에 들어간다.

**뭔가 잘못되면** 앱을 종료하면 키보드가 원래대로 돌아간다(⌘Q, 강제 종료 모두).
그래도 이상하면:

```bash
make reset-hid     # 또는 hidutil property --set '{"UserKeyMapping":[]}'
```

재부팅해도 원래대로 돌아온다. 키보드가 잠기는 일은 없다 —
최악의 경우 Caps Lock 과 Right Option 이 아무 일도 안 하는 상태가 될 뿐이다.

**GitHub 동기화는 선택 사항이다.** Mac 이 하나면 설정하지 않아도 된다.

## 요구 사항

macOS 14 이상, Xcode 26 이상. 외부 의존성 없음.

## 빌드

```
make build     # 빌드
make run       # 빌드 후 실행 (개발용)
make install   # /Applications 로 설치하고 실행
make test      # 유닛 테스트
make icon      # 아이콘 다시 생성 (Tools/make-icon.swift)
make reset-hid # 비정상 종료 후 키보드 복구
```

**로그인 시 자동 실행을 쓰려면 `make install` 로 설치한 뒤 켜야 한다.**
`SMAppService` 는 등록 시점의 앱 경로를 기억하므로, `build/` 안에서 등록하면
앱을 옮기는 순간 조용히 실패한다. 설정 창에 이 경고가 뜬다.

## 메뉴바 앱

Dock 아이콘이 없는 메뉴바 전용 앱(`LSUIElement`)이다. 메뉴바 아이콘은 상태를
나타낸다 — 권한 없음 / 정지 / 동작 중.

```
동작 중 · 단축키 28개
────────────────────────────
✓ Enabled
────────────────────────────
Open Key Layout...
내보낼 변경 있음
Export to GitHub
Import from GitHub...
Settings...                ⌘,
────────────────────────────
Quit CapsLock Control      ⌘Q
```

평소엔 창을 띄우지 않는다. 다만 **첫 실행**이거나 **손쉬운 사용 권한이 없을 때**는
창을 띄워야 무엇을 해야 할지 알 수 있으므로 자동으로 연다.

`LSUIElement` 앱에서는 SwiftUI 가 `Window` 씬을 자동으로 만들지 않는다. 그래서
창을 여는 `openWindow` 액션을 메뉴바 라벨이 뜰 때 `WindowOpener` 에 등록해 두고
AppKit 쪽에서도 꺼내 쓴다. `Settings` 씬도 메뉴바 전용 앱에서 열기가 불안정해서
평범한 `Window` 로 만들었다.

**단축키로 CapsLock Control 자신을 여는 경우**는 `applicationShouldHandleReopen` 에서
처리한다. 메뉴바 앱은 "앱을 앞으로 가져오기" 와 "창을 띄우기" 가 분리돼 있어서,
이 훅이 없으면 단축키를 눌러도 아무 일도 일어나지 않는다.

## 동작 원리

### 왜 event tap 만으로는 안 되는가

Caps Lock 의 토글과 LED 는 세션 event tap 보다 **아래 계층(HID 드라이버)** 에서 처리된다.
event tap 에서 이벤트를 버려도 LED 는 켜지고 caps 상태는 바뀐다. 게다가 macOS 는
Caps Lock 에 hold-delay 를 걸기 때문에 레이어 키로 쓰면 반응이 눈에 띄게 느리다.
Karabiner 가 가상 HID 드라이버를 만드는 이유가 이것이다.

### CapsLock Control 의 방식: HID 리맵 + 얇은 event tap

드라이버를 만드는 대신 Apple 이 제공하는 `/usr/bin/hidutil` 의 `UserKeyMapping` 을 쓴다.

| 물리 키 | HID 리맵 후 | 처리 주체 |
|---|---|---|
| Caps Lock | F19 | CapsLockControl event tap (레이어 A) |
| Right Option | F20 | CapsLockControl event tap (레이어 B) |
| Right Command | F18 | macOS 입력 소스 단축키 (CapsLock Control 은 손대지 않고 통과시킨다) |
| fn | Left Control | macOS (선택 · `modifiers.swapFnAndLeftControl`) |
| Left Control | fn | macOS (선택 · 위와 한 쌍) |

fn 스왑은 기본적으로 꺼져 있고 Status 탭에서 켠다. Apple 키보드(내장·Magic
Keyboard)에서만 동작한다. fn 은 일반 키보드 usage page 가 아니라 Apple vendor
top case page(0xFF) 에 있는데, hidutil 이 그 페이지도 다룬다. 양방향 두 줄을
함께 걸어야 한다. 한쪽만 걸면 두 키가 모두 Control 이 된다.

이렇게 하면 event tap 이 **모디파이어를 전혀 다루지 않는다.** 이벤트 합성도, 플래그
조작도, 재진입 방지도 필요 없다. 남는 일은 "F19/F20 눌림 추적"과 "레이어가 켜져
있을 때의 일반 키 처리"뿐이다.

성질:

- private API 아님, 커널 확장 아님
- 영구 설정이 아니다. 재부팅/로그아웃하면 사라진다
- 앱 종료(⌘Q, SIGTERM 포함) 시 자동으로 원복한다
- 명령 실행 시점에 붙어 있던 키보드에만 적용된다 → 새 키보드가 붙으면 다시 건다

### 강제 종료 후 복구

앱이 크래시하면 매핑이 남는다. Caps Lock 과 Right Option 이 아무 일도 하지 않는
상태가 되며(키보드가 잠기지는 않는다), 아래 명령으로 즉시 복구된다.

```
make reset-hid
# 또는
hidutil property --set '{"UserKeyMapping":[]}'
```

앱 안의 "HID 매핑 강제 해제" 버튼도 같은 일을 한다. 재부팅해도 원복된다.

## 설정 파일

`~/Library/Application Support/CapsLockControl/shortcuts.json`

처음 실행할 때 자동으로 만들어진다. 번들 ID 를 소스에 못 박지 않고, 앱 이름으로
이 Mac 에 실제로 설치된 앱을 찾아 그 번들 ID 를 쓴다. 집 Mac 과 회사 Mac 에
설치된 앱이 달라도 각자 맞는 값으로 생성된다.

```json
{
  "version": 1,
  "defaults": {
    "whenAlreadyActive": "hide",
    "unmappedKeyPolicy": "swallow",
    "capsLockTapTogglesCapsLock": true,
    "layerTapTimeoutMilliseconds": 250
  },
  "rightCommand": { "action": "f18" },
  "modifiers": { "swapFnAndLeftControl": true },
  "layers": {
    "capsLock": {
      "c": { "type": "application",
             "bundleIdentifier": "com.google.Chrome",
             "displayName": "Google Chrome" },
      "left": { "type": "media", "command": "previous", "target": "system" }
    },
    "rightOption": {}
  }
}
```

- 키 식별자
  - 알파벳/숫자: `a`~`z`, `0`~`9`
  - 기호: `grave` `minus` `equal` `leftBracket` `rightBracket` `backslash`
    `semicolon` `quote` `comma` `period` `slash`
  - 방향키: `left` `right` `up` `down`
  - 기타: `space` `return` `tab` `delete` `escape`
  - 기호는 `","` `"."` `"/"` `"\\"` 처럼 문자로 써도 읽힌다(별칭). 다만 앱이
    저장할 때는 항상 이름 쪽으로 정리한다. JSON 에서 백슬래시를 이스케이프하는
    번거로움을 피하려는 것이고, 같은 물리 키에 두 항목이 생기지 않도록
    별칭으로 적힌 기존 항목은 지워진다.
- `whenAlreadyActive`: `nothing` | `hide` | `switchToPrevious` — 키마다 덮어쓸 수 있다
- `rightCommand.action`: `f18` | `none` (`none` 이면 오른쪽 ⌘ 를 건드리지 않는다)
- `media.command`: `playPause` | `next` | `previous`, `target`: `system` | `spotify`
- `modifiers.swapFnAndLeftControl`: fn ↔ 왼쪽 Control 맞바꾸기 (없으면 꺼짐)

**직접 고쳐도 된다.** 앱이 설정 폴더를 감시하고 있어서 저장하는 순간 다시 읽는다.
재시작할 필요가 없다.

안전 장치:

- 저장은 항상 atomic. 중간에 죽어도 파일이 반쪽으로 남지 않는다.
- 파일이 깨져 있으면 **지우지 않고** `shortcuts.broken-<시각>.json` 으로 보관한 뒤
  기본값으로 시작한다.
- 파일 버전이 앱보다 높으면 읽기 전용으로 다룬다. 다른 Mac 의 새 버전이 만든
  설정을 이 Mac 이 덮어쓰는 사고를 막는다.
- 모르는 키·레이어·동작 타입을 만나도 죽지 않는다. 그 항목만 건너뛰고 경고로 남긴다.

## 다른 앱의 단축키 부르기 (keyStroke)

CapsLock Control 이 키 조합을 대신 눌러 주는 동작이다. 그 조합을 전역 단축키로 등록해 둔
앱이 평소처럼 반응한다.

```json
"a": {
  "type": "keyStroke",
  "key": "a",
  "modifiers": ["control", "option", "shift"],
  "label": "NoCan 토글"
}
```

**왜 필요한가.** Caps Lock 은 이 앱에서 F19 로 바뀌기 때문에 다른 앱이 "Caps+A" 를
직접 등록할 수 없다. 그래서 Caps+A 를 CapsLock Control 이 받아서 ⌃⌥⇧+A 를 발생시키고,
받는 앱은 원래대로 ⌃⌥⇧+A 를 등록해 둔다. Karabiner 로 Right Option 을 Meh(⌃⌥⇧)
로 쓰던 구조를 그대로 유지하는 셈이다.

**왜 통하는가.** `RegisterEventHotKey`(Carbon) 로 등록된 단축키는 WindowServer 가
이벤트 스트림을 보고 판정한다. 우리가 만든 이벤트도 수정자 플래그가 맞으면
하드웨어로 누른 것과 똑같이 처리된다.

**무한 루프 방지.** 우리가 만든 이벤트는 우리 event tap 에도 다시 들어온다.
표시를 남기지 않으면 Caps+A → 조합 발생 → 탭이 다시 잡음 → 또 발생 이 끝없이
반복된다. 그래서 모든 합성 이벤트의 `eventSourceUserData` 에 표시를 박고, 탭은
그 표시를 보면 손대지 않고 흘려보낸다.

GUI 에서는 빈 키를 클릭해 앱 피커를 열고 맨 아래 "키 조합 보내기" 칸을 클릭한 뒤
원하는 조합을 누른다. 조합을 녹화할 때는 **왼쪽** 수정자를 써야 한다.
Right Option 은 이 앱이 레이어 키로 가져갔기 때문이다.

## Caps Lock 단독 탭

Caps Lock 을 **다른 키와 조합하지 않고 짧게** 눌렀다 떼면 원래 기능(대문자 고정)이
동작한다. 조합해서 쓰면 레이어, 혼자 톡 치면 Caps Lock 이다.

판정은 두 조건을 모두 만족해야 한다.

- 누르고 있는 동안 **다른 키를 하나도 쓰지 않았다** (상태 기계가 기억한다)
- 누른 시간이 `layerTapTimeoutMilliseconds`(기본 250ms) 이내다

시간 조건이 필요한 이유는, 레이어를 켰다가 마음이 바뀌어 그냥 뗀 경우와
구분해야 하기 때문이다.

CGEvent 로 Caps Lock 키를 합성해도 소용없다. Caps Lock 토글은 HID 계층에서
처리되기 때문이다 — event tap 으로 Caps Lock 을 막지 못하는 것과 같은 이유다.
대신 IOKit 공개 API(`IOHIDSetModifierLockState`) 로 상태를 직접 바꾼다.

## 앱 토글 (이미 맨 앞일 때)

같은 단축키를 다시 눌렀을 때의 동작이다. Keyboard Maestro 의 Toggle 과 같은 개념.

| 값 | 동작 |
|---|---|
| `hide` (기본) | ⌘H 와 같다. macOS 가 알아서 다음 앱을 앞으로 가져온다 |
| `switchToPrevious` | 이 앱 직전에 앞에 있던 앱으로 되돌아간다. 기록이 없으면 `hide` 로 폴백 |
| `nothing` | 아무것도 안 한다 |

`hide` 를 기본값으로 둔 이유는 상태를 안 들고 있어서다. 직전 앱을 기억하는 방식은
그 앱이 종료됐거나 중간에 다른 앱을 거쳤을 때 기록이 어긋날 수 있다.

**연타 억제**: 앱 활성화가 비동기라서 아주 빠르게 두 번 누르면 두 번째 판정 시점에
아직 frontmost 가 안 바뀌어 있을 수 있다. 그러면 토글이 타이밍에 따라 먹기도 하고
안 먹기도 한다. 그 애매함을 없애려고 같은 앱에 대한 250ms 이내 재입력은 무시한다.

## 미디어 제어

`target: "system"` (기본) 은 하드웨어 미디어 키와 똑같은 시스템 이벤트를 만들어 보낸다
(IOKit 공개 헤더 `ev_keymap.h` 의 `NX_KEYTYPE_*`). macOS 가 "지금 재생 중인 앱"에게
전달하므로 Spotify 가 재생 중이면 Spotify 가 받는다. 권한이 따로 필요 없고
Apple Music 으로 갈아타도 그대로 동작한다.

`target: "spotify"` 는 Spotify 에만 AppleScript 로 직접 명령한다. 무엇이 재생 중이든
항상 Spotify 를 제어하지만 처음 한 번 자동화 권한을 물어본다. Spotify 가 실행 중이
아니면 실행시키지 않고 그냥 알려 준다.

MediaRemote 같은 private framework 는 쓰지 않는다.

## 구조

```
CapsLockControl/
  Core/     AppKit 의존 없는 순수 로직. 유닛 테스트 대상.
    KeyCode.swift            가상 키코드 ↔ 문자열 식별자 표 (설정/UI 공용)
    LayerKey.swift           capsLock / rightOption
    ShortcutAction.swift     application / media / (확장 자리)
    BindingTable.swift       키코드로 정규화된 조회 표
    CapsLockControlConfig.swift     디스크 스키마 + version/migration
    ConfigStore.swift        atomic 저장 · 손상 파일 백업 · 폴더 감시
    LayerStateMachine.swift  눌림·뗌 순서를 다루는 순수 상태 기계
    UnmappedKeyPolicy.swift  등록되지 않은 키 정책 (기본: 삼킴)
  Engine/   시스템과 맞닿는 부분
    HIDRemapper.swift        hidutil 래핑 + 키보드 핫플러그 재적용
    EventTapController.swift 전용 스레드 위의 CGEventTap, 꺼지면 자동 재활성화
    KeyboardEngine.swift     탭 ↔ 상태 기계 ↔ 실행 연결
    ActionExecutor.swift     앱 실행/활성화/토글 (MainActor)
    MediaController.swift    시스템 미디어 키 · Spotify AppleScript
    KeyStrokeSender.swift    다른 앱의 전역 단축키를 부르는 합성 이벤트
    FrontmostAppTracker.swift 직전 앱 기록 (switchToPrevious 전용)
    DefaultConfiguration.swift 첫 실행 시 기본 설정 생성
  App/      SwiftUI 진입점 · AppDelegate · EngineModel
  UI/
    MainWindowView.swift     헤더 + 배너 + 탭
    KeyboardEditorView.swift QWERTY 배열, 레이어 전환, Used/Available
    KeyboardLayout.swift     물리 배치(어느 자리에 얼마나 넓게)
    KeycapView.swift         키 한 칸 (두 레이어 공용) + 쓸 수 없는 키
    KeyDetailView.swift      선택한 키 상세 + 편집 버튼
    ApplicationPickerView.swift 앱 검색 팝오버
    ApplicationCatalog.swift 실행 중 / 설치된 앱 목록과 검색
    KeyStrokeRecorder.swift  보낼 조합을 눌러서 지정하는 칸 (NSView)
    StatusView.swift         HID 매핑 · 설정 파일 · 로그
    AppIconProvider.swift    앱 아이콘 캐시
```

### 스레드 규칙

이벤트 탭 콜백은 **메인 스레드가 아닌 전용 스레드**에서 돈다. 메인 스레드가 잠깐이라도
막히면 탭이 타임아웃으로 꺼지면서 키보드 입력이 통째로 먹통이 되기 때문이다.
콜백 안에서는 락 아래 상태 갱신만 하고, 앱 실행 같은 일은 `Task { @MainActor }` 로 넘긴다.

### 상태 기계 불변식

- 삼켜서 keyDown 을 없앤 키는 keyUp 도 반드시 삼킨다 (레이어를 먼저 떼도 짝이 맞는다)
- 오토리핏 keyDown 은 동작을 다시 실행하지 않는다
- 레이어 키를 겹쳐 누르면 마지막에 누른 쪽이 이긴다
- 탭이 재활성화되면 눌림 상태를 전부 잊는다

## 창 구성

```
┌─ [ Key Layout ] [ Status ] ──────────────────┐  ← 탭 (타이틀바)
│ CapsLockControl                    [Caps][R-Opt] 정지 │  ← 항상 보이는 헤더
│ 동작 중 · 단축키 24개                          │     레이어 표시등은 실시간
├───────────────────────────────────────────────┤
│ [ Caps Lock ][ Right Option ]  Used 24  Avail 16│
│                                               │
│ esc `  1 2 3 4 5 6 7 8 9 0  -  =  [delete]    │
│ [tab]  Q W E R T Y U I O P  [  ]  \           │
│ [caps ]  A S D F G H J K L  ;  '  [return]    │
│ [ shift ]  Z X C V B N M  ,  .  /  [ shift ]  │
│ fn ctrl opt cmd [== space ==] cmd opt   ←↑↓→  │
└───────────────────────────────────────────────┘
```

- **실제 맥북 배치**를 따른다. tab / caps / shift / return / delete 가 제자리에 있고
  너비도 실제 비율(tab 2u, shift 2.5u, space 5u …)이다. 스페이스는 맥북처럼
  C 왼쪽 모서리에서 M 오른쪽 모서리까지다. 방향키는 네 개 모두 반 높이인
  역T자이고 ← ↓ → 가 바닥에 나란히 붙는다.
- `전체 키보드` / `단축키 키만` 을 전환할 수 있다. 앞쪽은 shift·option 처럼
  **단축키로 쓸 수 없는 키까지 회색으로** 그려서 무엇이 리맵돼 있는지 보여 준다
  (caps lock 은 지금 보고 있는 레이어면 강조되고, 오른쪽 command 는 `→ F18`,
  fn/control 은 스왑 상태를 표시한다). 뒤쪽은 걸 수 있는 키만 남긴다.
  모디파이어를 지워도 방향키는 원래 자리(오른쪽 끝)에 남는다.
- 두 레이어가 **같은 키보드 뷰를 공유**한다. 레이어를 바꾸면 키캡에 넘기는
  `action` 만 달라진다.
- 키캡에는 키 문자 · 앱 아이콘 · 앱 이름(두 줄까지)이 들어간다.
  빈 키는 점선 테두리 + `+` + `Available`.
- 설치되지 않은 앱은 빨간 테두리와 **Missing** 으로 표시된다.
- 권한 경고 · 충돌 경고 · 엔진 시작/정지 · 레이어 표시등은 탭 밖에 있어서
  어느 탭에 있어도 보인다.

키캡의 앱 이름은 줄이지 않고 전체 이름을 그대로 쓴다. 첫 단어만 쓰면
"Google Chrome" 이 "Google" 이 되고, 마지막 단어만 쓰면
"Microsoft Remote Desktop Beta" 가 "Beta" 가 된다. 어느 휴리스틱도 맞지 않아서
두 줄까지 쓰고 넘치면 말줄임한다.

## 단축키 편집

키캡을 클릭해서 편집한다. 설정 파일을 직접 고치는 방법도 계속 유효하다.

| 조작 | 결과 |
|---|---|
| **빈 키 클릭** | 앱 피커가 바로 열린다 |
| **할당된 키 클릭** | 상세 패널 (변경 / 삭제 / 이미 맨 앞일 때 동작) |
| **키캡을 다른 키로 드래그** | 두 키의 동작이 **맞바뀐다**. 빈 키로 끌면 이동이 된다 |
| 삭제 | 즉시 Available |

### 앱 피커

경로나 bundle ID 를 직접 입력하지 않는다. 목록에서 고르기만 하면 된다.
검색은 Enter 없이 **한 글자 칠 때마다** 걸러지고, `localizedName` 과
`bundleIdentifier` 를 대소문자 구분 없이 부분 일치로 본다.

- **실행 중** — `NSWorkspace.runningApplications` 중 `activationPolicy == .regular`
  인 것만. 메뉴바 전용 앱과 백그라운드 프로세스는 뺀다. 앱을 켜고 끄면 목록도 따라 바뀐다.
- **설치됨** — 실행 중이 아닌 앱에도 단축키를 걸 수 있어야 하므로 함께 보여 준다.
  처음 피커를 열 때 한 번만 훑고(백그라운드), 실행 중 목록과 겹치는 것은 뺀다.
- **미디어** — Play/Pause · Next · Previous.
- 고르려는 앱이 같은 레이어의 다른 키에 이미 걸려 있으면 `이미 C` 처럼 알려 준다.

### 충돌

이미 쓰는 키에 다른 동작을 넣으려 하면 무엇이 무엇으로 바뀌는지 보여 주고 묻는다.

```
Caps + C 는 현재 Google Chrome 에 할당되어 있습니다.
Safari 으로 교체할까요?              [취소] [교체]
```

드래그로 옮기는 것은 **맞바꾸기**라서 아무것도 잃지 않는다. 그래서 확인을 묻지 않는다.

### 개발용 플래그

클릭 자동화 없이 앱 피커 팝오버 모양을 확인할 때 쓴다. DEBUG 빌드만.

```
open build/Build/Products/Debug/CapsLockControl.app --args -openPicker q
```

## GitHub 설정 동기화 — Export / Import

집 Mac 과 회사 Mac 이 같은 설정을 쓴다. 설정 › 동기화에 저장소 주소를 넣고 쓴다.

| 동작 | 하는 일 |
|---|---|
| **Export** | 지금 설정을 **시각 + Mac 이름이 붙은 새 스냅샷**으로 올린다. 기존 것은 지우지 않는다 |
| **Import** | 쌓인 스냅샷 중 하나를 고르고, 무엇이 달라지는지 본 뒤 **항목을 체크해서** 가져온다 |

```
keylayer-config/
  shortcuts.json                              ← 가장 최근 export (GitHub 웹에서 읽기용)
  snapshots/
    2026-09-14_153045_my-mbp.json
    2026-09-13_091201_my-imac.json
```

### 왜 자동 병합이 아닌가

처음에는 3-way 자동 병합으로 만들었다가 이 방식으로 바꿨다.

- **Export 는 지우는 게 없다.** 잘못 올려도 이전 스냅샷이 그대로 있어서 되돌리는 게
  Import 한 번이다. 병합은 결과를 덮어쓰므로 잘못되면 복구가 어렵다.
- **골라 가져오기가 더 강하다.** "회사 Mac 의 Caps+C 만 가져오기" 는 자동 병합이
  표현할 수 없다. 반대로 자동 병합이 하던 "양쪽 변경을 모두 살리기" 는
  체크박스를 전부 켜면 된다. 표현력이 상위 집합이다.
- **공통 조상을 추적하지 않는다.** 병합은 base 를 잘못 잡으면 조용히 틀린 결과를
  낸다. 이 방식엔 그 경로가 없다.

대가는 자동이 아니라는 것이다. 그래서 "내보낼 변경 있음" 을 상태로 알려 준다.

### Import 화면

스냅샷을 고르면 지금 설정과의 차이가 항목별로 뜬다. 각 줄에 `추가` / `변경` / `삭제`
표시와 `현재 값 → 스냅샷 값` 이 보인다. 처음엔 전부 체크돼 있어서 그대로 누르면
전체 가져오기가 된다. `전체 선택` · `전체 해제` 버튼도 있다.

Import 는 이 Mac 의 설정만 바꾼다. GitHub 에는 아무것도 올리지 않는다.

### 인증

토큰·비밀번호·SSH 키를 앱에 저장하지 않는다. 이미 이 Mac 에 설정된 SSH 인증을
그대로 쓴다. 프롬프트로 멈추지 않도록 `GIT_TERMINAL_PROMPT=0` 과
`ssh -o BatchMode=yes` 를 걸고, 모든 git 호출에 타임아웃을 둔다. SSH 키가
ssh-agent 에 없으면 멈추지 않고 "인증 실패" 로 끝난다.

### 저장소를 다루는 방식

- clone 은 `~/Library/Application Support/CapsLockControl/sync/` 에 두고 **버리는 작업
  공간**으로 취급한다. 설정 폴더 자체를 저장소로 만들지 않는 이유는, git 이 파일을
  갈아치우는 동안 앱의 파일 감시자가 중간 상태를 읽을 수 있기 때문이다.
- Export 전에 `reset --hard origin/<branch>` + `clean -fd` 로 원격에 맞춘 뒤
  새 스냅샷만 올린다. 그래서 우리 커밋은 항상 원격의 자손이고, push 가 거부되거나
  merge commit 이 생기지 않는다. 앞선 실패가 남긴 찌꺼기도 함께 정리된다.
- 커밋이 하나도 없는 새 저장소도 처리한다. `rev-parse --abbrev-ref HEAD` 는 그때
  실패하므로 브랜치 이름은 `symbolic-ref --short HEAD` 로 읽고,
  `origin/<branch>` 가 없으면 reset 을 건너뛴다.
- 스냅샷은 자동으로 지우지 않는다. 하나에 4KB 남짓이라 쌓여도 문제가 되지 않고,
  이력을 지우는 것이야말로 이 방식의 장점을 없애는 일이다.

## 아이콘

`Tools/make-icon.swift` 가 코드로 그린다. 바꾸려면 그 파일을 고치고
`make icon && make build`.

핵심은 **크기별로 디테일을 줄이는 것**이다. 512px 에서 괜찮은 그림을 그대로 16px 로
줄이면 얼룩이 된다. 처음엔 SF Symbol 키보드를 얹었는데 16~32px 에서 흐릿한
덩어리가 됐다. 지금은 키보드를 직접 그리고 한 줄의 키 개수를 크기에 따라 3~6개로
바꾼다. 왼쪽 아래 키 하나만 파란색인데 그게 "레이어 키" 이고, 작은 크기에서 색으로
구분되는 유일한 요소다.

**주의**: 같은 경로에 다시 빌드하면 Finder 와 앱 안의 키캡이 옛 아이콘을 계속
보여 준다. LaunchServices 아이콘 캐시가 경로 단위로 잡고 있어서다.
`make refresh-icon-cache` 로 갱신한다.

## 기존 도구와의 공존

개발/검증 중에는 Karabiner 와 Raycast 를 지우지 않는다. 다만 같은 키를 두 도구가
동시에 가로채면 겹치므로, 테스트할 때는 Karabiner 에 **빈 프로필**을 만들어 잠시
전환한다 (Settings → Profiles → Add profile). 되돌리기가 한 번의 클릭이다.

CapsLock Control 은 다른 앱을 절대 자동 종료하지 않는다. 실행 중이면 창에 경고만 띄운다.
