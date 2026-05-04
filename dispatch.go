package main

import (
	"encoding/json"
	"fmt"
)

// Request is the wire-level request envelope shared by HTTP and Bluetooth transports.
// Bluetooth uses a single newline-delimited JSON stream where each line carries a Request.
// HTTP wraps these per-route — the dispatcher accepts the same shape from either path.
type Request struct {
	ID      int    `json:"id,omitempty"`
	Type    string `json:"type"`
	Serial  string `json:"serial,omitempty"`
	Key     string `json:"key,omitempty"`
	Text    string `json:"text,omitempty"`
	Display *int   `json:"display,omitempty"`
}

type Response struct {
	ID    int         `json:"id,omitempty"`
	OK    bool        `json:"ok"`
	Data  interface{} `json:"data,omitempty"`
	Error string      `json:"error,omitempty"`
}

// Dispatch executes a single Request and returns its Response. It never returns an error
// directly — failures are encoded in resp.OK / resp.Error so transports can serialize uniformly.
func Dispatch(req Request) Response {
	resp := Response{ID: req.ID}

	switch req.Type {
	case "listDevices":
		devices, err := ListDevices()
		if err != nil {
			resp.Error = err.Error()
			return resp
		}
		if devices == nil {
			devices = []Device{}
		}
		resp.OK = true
		resp.Data = devices

	case "listDisplays":
		if req.Serial == "" {
			resp.Error = "missing serial"
			return resp
		}
		displays, err := ListDisplays(req.Serial)
		if err != nil {
			resp.Error = err.Error()
			return resp
		}
		if displays == nil {
			displays = []Display{}
		}
		resp.OK = true
		resp.Data = displays

	case "keyevent":
		if req.Serial == "" {
			resp.Error = "missing serial"
			return resp
		}
		code, ok := keyMap[req.Key]
		if !ok {
			resp.Error = "unknown key: " + req.Key
			return resp
		}
		displayID := -1
		if req.Display != nil {
			displayID = *req.Display
		}
		if err := SendKeyEvent(req.Serial, code, displayID); err != nil {
			resp.Error = err.Error()
			return resp
		}
		resp.OK = true

	case "text":
		if req.Serial == "" {
			resp.Error = "missing serial"
			return resp
		}
		if req.Text == "" {
			resp.OK = true
			return resp
		}
		displayID := -1
		if req.Display != nil {
			displayID = *req.Display
		}
		if err := SendText(req.Serial, req.Text, displayID); err != nil {
			resp.Error = err.Error()
			return resp
		}
		resp.OK = true

	default:
		resp.Error = fmt.Sprintf("unknown type: %q", req.Type)
	}

	return resp
}

// MarshalResponse is a tiny helper used by the Bluetooth handler so it doesn't need to
// import encoding/json directly.
func MarshalResponse(r Response) ([]byte, error) {
	return json.Marshal(r)
}
