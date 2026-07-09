//go:build tools

// Package tools pins build-time tool dependencies so `go mod tidy` keeps them in
// go.mod for reproducible `gomobile bind` builds. It is never compiled into the
// library (guarded by the `tools` build tag).
package tools

import (
	_ "golang.org/x/mobile/bind"
)
