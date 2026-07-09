// Package gtlv is a gomobile-friendly wrapper around
// github.com/cca2878/gtlv-go, exposing a flat API (string in / string out)
// suitable for `gomobile bind` into an Android AAR (or iOS framework).
//
// All the real work — GeeTest V3 click/slide solving, wasm inference,
// w-parameter crypto and protocol orchestration — lives in the upstream
// library. This package only adapts its idiomatic Go surface (context,
// functional options, typed errors, slices) into the restricted type set
// gomobile can bind for Java/Kotlin/Swift. The upstream library stays pure
// Go-native and unaware of gomobile; keeping the wrapper in its own module
// isolates the cgo/NDK/AAR concerns here.
//
// License: AGPL-3.0 (inherited from the upstream library it links).
package gtlv

import (
	"context"

	"github.com/cca2878/gtlv-go/pkg/client"
	"github.com/cca2878/gtlv-go/pkg/solver"
)

// Client is a reusable, concurrency-safe handle bundling the local solver and
// the GeeTest V3 network client. Build it once and reuse it across challenges;
// call Close when done.
//
// The fields are unexported on purpose: to Java/Kotlin the Client is an opaque
// handle exposing only the methods below.
type Client struct {
	solver *solver.CaptchaSolver
	v3     *client.V3Client
}

// NewClient builds a Client.
//
//   - modelDir: directory holding the two model files (yolo…onnx +
//     siamese…nnef.tgz). On Android, extract them from assets/resources into an
//     app-private directory first and pass that path.
//   - cacheDir: a persistent, writable directory for the wazero compilation
//     cache. The first launch AOT-compiles the wasm (cold, a few seconds); later
//     launches reuse the cache (warm). Pass an app-private writable directory.
//   - maxAttempts: number of image re-fetch retries on model misdetection;
//     pass <= 0 to use the library default.
func NewClient(modelDir, cacheDir string, maxAttempts int) (*Client, error) {
	s, err := solver.NewCaptchaSolver(
		solver.WithModelDir(modelDir),
		solver.WithCacheDir(cacheDir),
	)
	if err != nil {
		return nil, err
	}

	var opts []client.Option
	if maxAttempts > 0 {
		opts = append(opts, client.WithMaxAttempts(maxAttempts))
	}

	return &Client{solver: s, v3: client.NewV3Client(opts...)}, nil
}

// GetValidate solves the challenge identified by (gt, challenge) and returns the
// GeeTest `validate` string to submit to your business backend. Click and slide
// are auto-dispatched by challenge type.
//
// On failure it returns a non-nil error whose message carries the reason (the
// server-reported result, or a transport/config error). Both a verification
// failure and a network failure surface as an error here; inspect the message to
// distinguish them.
func (c *Client) GetValidate(gt, challenge string) (string, error) {
	return c.v3.GetValidate(context.Background(), gt, challenge, c.solver)
}

// Close releases the underlying wasm runtime. The Client must not be used after
// Close returns.
func (c *Client) Close() error {
	return c.solver.Close()
}
