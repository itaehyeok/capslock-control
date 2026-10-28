# CapsLockControl 개발용 단축 명령.
# 빌드 산출물은 프로젝트 안 build/ 로 모은다 (DerivedData 경로 추적이 귀찮아서).
PROJ  := CapsLockControl.xcodeproj
SCHEME:= CapsLockControl
# .noindex 로 끝나는 폴더는 Spotlight 가 색인하지 않는다.
# 그냥 build/ 로 두면 make install 후 /Applications 사본과 빌드 사본이
# 둘 다 Spotlight 에 떠서 어느 쪽이 실행될지 헷갈린다.
BUILD := $(CURDIR)/build.noindex
APP   := $(BUILD)/Build/Products/Debug/CapsLockControl.app

.PHONY: build run test clean stop reset-hid install icon refresh-icon-cache release

build:
	@xcodebuild -project $(PROJ) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD) build | tail -20

run: build stop
	@open $(APP)
	@echo "실행: $(APP)"

test:
	@xcodebuild -project $(PROJ) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD) test 2>&1 | tail -40

stop:
	@pkill -x CapsLockControl 2>/dev/null || true
	@sleep 0.5

# 로그인 시 자동 실행을 쓰려면 반드시 이 위치에서 실행해야 한다.
# SMAppService 는 등록 시점의 앱 경로를 기억하기 때문이다.
# 서명은 스크립트가 고른다. 공개 릴리스를 깐 Mac 에서 권한이 끊기지 않게 하려는 것이다.
install:
	@./Tools/install.sh

# 앱이 비정상 종료되어 Caps Lock 등이 먹통일 때 수동 복구용.
# 아이콘을 코드로 그린다. 디자인을 바꾸려면 Tools/make-icon.swift 를 고친다.
icon:
	@rm -rf $(BUILD)/AppIcon.iconset
	@mkdir -p $(BUILD)
	@xcrun swiftc -O -o $(BUILD)/make-icon Tools/make-icon.swift
	@$(BUILD)/make-icon $(BUILD)/AppIcon.iconset
	@cp $(BUILD)/AppIcon.iconset/*.png CapsLockControl/Assets.xcassets/AppIcon.appiconset/
	@echo "아이콘을 다시 생성했습니다. 이제 make build 하세요."
	@echo "옛 아이콘이 남으면 LaunchServices 캐시입니다. make refresh-icon-cache"

# 같은 경로에 다시 빌드하면 Finder 와 앱 키캡이 옛 아이콘을 붙들고 있다.
# 등록을 지웠다 다시 하면 갱신된다.
LSREG := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
refresh-icon-cache:
	@$(LSREG) -u $(APP) 2>/dev/null || true
	@sleep 1
	@$(LSREG) -f $(APP) 2>/dev/null || true
	@echo "아이콘 캐시를 갱신했습니다."

# 남에게 나눠 줄 DMG 를 만든다. Developer ID 인증서와 공증 자격증명이 필요하다.
# 없으면 스크립트가 무엇을 어디서 만들어야 하는지 알려 준다.
release:
	@VERSION=$(VERSION) ./Tools/release.sh

reset-hid:
	@hidutil property --set '{"UserKeyMapping":[]}' >/dev/null
	@echo "HID 리맵을 모두 해제했습니다."

clean:
	@rm -rf $(BUILD) $(CURDIR)/dist.noindex
