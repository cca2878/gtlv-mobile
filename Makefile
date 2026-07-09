# Makefile for gtlv-mobile — gomobile wrapper of gtlv-go → Android AAR

GOMOBILE := gomobile
# wazero's compiler backend supports only arm64/amd64, and the upstream library
# fails to compile on other arches by design (pkg/solver/unsupported.go). So bind
# only the matching Android ABIs — arm64-v8a and x86_64 — mirroring the upstream
# platform support table. armeabi-v7a / x86 are intentionally excluded.
ANDROID_TARGETS := android/arm64,android/amd64
ANDROID_API := 21
# gomobile appends the Go package name (gtlv) → final Java package com.cca2878.gtlv
JAVAPKG := com.cca2878
AAR := gtlv.aar

.PHONY: deps bind-android vet check clean help

# Install the gomobile toolchain. Requires the Android SDK + NDK already present
# (in CI they come from setup-android); ANDROID_HOME / NDK must be set.
deps:
	go install golang.org/x/mobile/cmd/gomobile@latest
	go install golang.org/x/mobile/cmd/gobind@latest
	$(GOMOBILE) init

# Build the Android AAR (+ sources jar). Needs ANDROID_HOME and an NDK.
bind-android:
	$(GOMOBILE) bind -target=$(ANDROID_TARGETS) -androidapi $(ANDROID_API) -javapkg=$(JAVAPKG) -o $(AAR) .
	@echo "built $(AAR)"

# Native sanity (no gomobile/NDK needed): does the wrapper compile against the
# upstream library and vet cleanly? This is what PR CI runs.
check vet:
	gofmt -l . | (! grep .) || (echo "not gofmt-clean"; exit 1)
	go vet ./...
	go build ./...

clean:
	rm -f $(AAR) gtlv-sources.jar

help:
	@echo "  deps          安装 gomobile/gobind（需已装 Android SDK+NDK）"
	@echo "  bind-android  gomobile bind → $(AAR)（arm64-v8a + x86_64）"
	@echo "  check         本地/PR 校验：gofmt + vet + build（无需 NDK）"
	@echo "  clean"
