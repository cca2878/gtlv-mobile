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
AAR := gtlv-mobile.aar
# 16 KB page alignment: Android 15 (API 35) devices use 16 KB memory pages and
# Google Play requires native libs to load on them. gomobile's libgojni.so is
# linked by the NDK lld via cgo/JNI; NDK r26 defaults to 4 KB pages, so its LOAD
# segments would be rejected on 16 KB-page devices. Pass max-page-size=16384 to
# lld to align them. Drop this once the CI NDK is bumped to r28+ (16 KB by default).
LDFLAGS := -extldflags=-Wl,-z,max-page-size=16384

# STRIP=true appends -s -w to strip Go's symbol table + DWARF. The consuming app's
# AGP/NDK strip only erases standard ELF symbols and cannot touch Go's own pclntab/
# symbol metadata, so a Release artifact still needs -s -w here to actually shrink;
# SNAPSHOT/PR CI keeps symbols for diagnosis. Only release CI passes STRIP=true.
ifeq ($(STRIP),true)
LDFLAGS := -s -w $(LDFLAGS)
endif

.PHONY: deps bind-android vet check clean help

# Install the gomobile toolchain. Requires the Android SDK + NDK already present
# (in CI they come from setup-android); ANDROID_HOME / NDK must be set.
deps:
	go install golang.org/x/mobile/cmd/gomobile@latest
	go install golang.org/x/mobile/cmd/gobind@latest
	$(GOMOBILE) init

# Build the Android AAR (+ sources jar). Needs ANDROID_HOME and an NDK.
# -trimpath drops absolute build paths from the binary (reproducibility; no path
# leakage). Enabled on every bind / all CIs.
bind-android:
	$(GOMOBILE) bind -trimpath -target=$(ANDROID_TARGETS) -androidapi $(ANDROID_API) -javapkg=$(JAVAPKG) -ldflags="$(LDFLAGS)" -o $(AAR) .
	@echo "built $(AAR)"

# Native sanity (no gomobile/NDK needed): does the wrapper compile against the
# upstream library and vet cleanly? This is what PR CI runs.
check vet:
	gofmt -l . | (! grep .) || (echo "not gofmt-clean"; exit 1)
	go vet ./...
	go build ./...

clean:
	rm -f $(AAR) gtlv-mobile-sources.jar

help:
	@echo "  deps          安装 gomobile/gobind（需已装 Android SDK+NDK）"
	@echo "  bind-android  gomobile bind → $(AAR)（arm64-v8a + x86_64）"
	@echo "  check         本地/PR 校验：gofmt + vet + build（无需 NDK）"
	@echo "  clean"
