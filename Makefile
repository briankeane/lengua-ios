ORIGINAL_REPO := $(HOME)/code/lengua-ios
SCHEME := Lengua
PROJECT := Lengua.xcodeproj
# Discover an available iOS 18.x simulator by UDID so the build doesn't pin a
# specific point release (e.g. 18.6) that may not exist on other machines/CI.
SIMULATOR_UDID := $(shell xcrun simctl list devices available | awk '/-- iOS 18\./{flag=1; next} /^-- /{flag=0} flag' | grep -m1 'iPhone' | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
DESTINATION := platform=iOS Simulator,id=$(SIMULATOR_UDID)
XCFLAGS := -skipMacroValidation CODE_SIGNING_ALLOWED=NO

.PHONY: generate build test lint format format-check setup-conductor release

generate:
	xcodegen generate

build: generate
	@test -n "$(SIMULATOR_UDID)" || (echo "No available iOS 18.x simulator found via 'xcrun simctl list devices available'." && exit 1)
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -destination "$(DESTINATION)" $(XCFLAGS)

test: generate
	@test -n "$(SIMULATOR_UDID)" || (echo "No available iOS 18.x simulator found via 'xcrun simctl list devices available'." && exit 1)
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination "$(DESTINATION)" $(XCFLAGS)

lint:
	swiftlint --strict

format:
	xcrun swift-format format -i --recursive Lengua LenguaTests

format-check:
	xcrun swift-format lint --strict --recursive Lengua LenguaTests

setup-conductor:
	@test -d $(ORIGINAL_REPO) || (echo "Original repo not found at $(ORIGINAL_REPO)." && exit 1)
	@for f in Secrets Secrets-Development Secrets-Local Secrets-Staging; do \
		test -f Lengua/Config/$$f.xcconfig \
			|| cp $(ORIGINAL_REPO)/Lengua/Config/$$f.xcconfig Lengua/Config/$$f.xcconfig; \
	done

release:
	bundle exec fastlane release_production
