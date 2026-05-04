//go:build !windows

package ble

import "fmt"

// Handler matches the Windows version's signature.
type Handler func(reqLine []byte) (respLine []byte)

// Start is a no-op on non-Windows builds; it always returns an error so callers can
// log a warning. The HTTP server on these platforms is unaffected.
func Start(h Handler) error {
	return fmt.Errorf("bluetooth: AF_BTH SPP server is Windows-only in this build")
}
