import Foundation

/// 앱을 바꿔 끼우는 셸 스크립트. 앱이 꺼지기를 기다렸다가 새 앱을 놓고 다시 연다.
///
/// 도는 앱은 자기 번들을 바꿀 수 없다. 그래서 따로 띄운 이 스크립트가 앱이 꺼진 뒤에 한다.
/// 꺼진 뒤라 실패해도 화면에 띄울 곳이 없으므로 단계마다 로그 파일에 남긴다 —
/// "업데이트를 눌렀더니 앱이 사라졌다" 를 로그만 보고 가를 수 있게.
///
/// 인자: ① 놓을 새 앱 ② 놓을 자리(지금 앱) ③ 기다릴 PID ④ 로그 파일
/// ⑤ 여는 명령(테스트용, 기본 `/usr/bin/open`)
enum UpdateHelperScript {

    /// `waitSeconds`: 앱이 꺼지기를 기다리는 시간. 넘기면 아무것도 바꾸지 않고 그만둔다.
    static func text(waitSeconds: Int = 30) -> String {
        """
        #!/bin/bash
        set -uo pipefail
        stage="$1"
        target="$2"
        pid="$3"
        log="$4"
        opener="${5:-/usr/bin/open}"
        backup="${target%.app}.previous-$$.app"
        trap 'rm -f "$0"' EXIT
        note() { printf '%s [update] %s\\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$log" 2>/dev/null || true; }
        for _ in $(seq 1 \(max(1, waitSeconds * 5))); do
          kill -0 "$pid" 2>/dev/null || break
          sleep 0.2
        done
        if kill -0 "$pid" 2>/dev/null; then
          note "앱이 \(waitSeconds)초 안에 꺼지지 않아 교체를 그만둠"
          rm -rf "$stage"
          exit 1
        fi
        if [ -e "$target" ] && ! mv "$target" "$backup"; then
          note "있던 앱을 비키지 못함: $target"
          rm -rf "$stage"
          exit 1
        fi
        if ! mv "$stage" "$target"; then
          note "새 앱을 놓지 못함: $target"
          if [ -e "$backup" ]; then mv "$backup" "$target"; fi
          exit 1
        fi
        if ! "$opener" "$target"; then
          note "새 앱을 열지 못함: $target"
          if [ -e "$backup" ]; then
            rm -rf "$target"
            mv "$backup" "$target"
            "$opener" "$target" || true
            note "있던 앱으로 되돌림: $target"
          fi
          exit 1
        fi
        if [ -e "$backup" ]; then rm -rf "$backup"; fi
        note "교체 완료: $target"
        exit 0
        """
    }
}
