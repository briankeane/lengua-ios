ORIGINAL_REPO := $(HOME)/code/lengua-ios
SCHEME := Lengua
PROJECT := Lengua.xcodeproj
DESTINATION := platform=iOS Simulator,name=iPhone 16,OS=18.6
XCFLAGS := -skipMacroValidation CODE_SIGNING_ALLOWED=NO

.PHONY: generate build test lint format format-check setup-conductor release

generate:
	xcodegen generate

build: generate
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -destination "$(DESTINATION)" $(XCFLAGS)

test: generate
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
