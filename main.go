package main

import (
	"embed"
	"encoding/json"
	"flag"
	"io/fs"
	"log"
	"net/http"

	"adb-remote/ble"
)

//go:embed web
var webFS embed.FS

var keyMap = map[string]int{
	"UP":      19,
	"DOWN":    20,
	"LEFT":    21,
	"RIGHT":   22,
	"OK":      23,
	"BACK":    4,
	"HOME":    3,
	"RECENTS": 187,
	"0":       7,
	"1":       8,
	"2":       9,
	"3":       10,
	"4":       11,
	"5":       12,
	"6":       13,
	"7":       14,
	"8":       15,
	"9":       16,
	"STAR":    17, // KEYCODE_STAR
	"POUND":   18, // KEYCODE_POUND
	"DEL":     67, // KEYCODE_DEL (backspace)
}

func main() {
	addr := flag.String("addr", "127.0.0.1:7878", "HTTP listen address")
	enableBT := flag.Bool("bluetooth", true, "Enable Bluetooth SPP listener (Windows only; ignored elsewhere)")
	flag.Parse()

	sub, err := fs.Sub(webFS, "web")
	if err != nil {
		log.Fatalf("embed sub: %v", err)
	}

	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.FS(sub)))
	mux.HandleFunc("/api/devices", handleDevices)
	mux.HandleFunc("/api/displays", handleDisplays)
	mux.HandleFunc("/api/keyevent", handleKeyEvent)

	if *enableBT {
		if err := ble.Start(bluetoothHandler); err != nil {
			log.Printf("bluetooth: disabled — %v", err)
		}
	}

	log.Printf("listening on http://%s", *addr)
	if err := http.ListenAndServe(*addr, mux); err != nil {
		log.Fatal(err)
	}
}

// bluetoothHandler decodes one JSON request line from a BT client, calls Dispatch,
// and serializes the Response. Returned bytes are sent back to the client (the ble
// package appends '\n').
func bluetoothHandler(line []byte) []byte {
	var req Request
	if err := json.Unmarshal(line, &req); err != nil {
		out, _ := json.Marshal(Response{OK: false, Error: "bad json"})
		return out
	}
	resp := Dispatch(req)
	log.Printf("bluetooth: %s ok=%v err=%q", req.Type, resp.OK, resp.Error)
	out, _ := json.Marshal(resp)
	return out
}

func handleDevices(w http.ResponseWriter, r *http.Request) {
	resp := Dispatch(Request{Type: "listDevices"})
	if !resp.OK {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": resp.Error})
		return
	}
	writeJSON(w, http.StatusOK, resp.Data)
}

func handleDisplays(w http.ResponseWriter, r *http.Request) {
	serial := r.URL.Query().Get("serial")
	resp := Dispatch(Request{Type: "listDisplays", Serial: serial})
	if !resp.OK {
		status := http.StatusBadGateway
		if resp.Error == "missing serial" {
			status = http.StatusBadRequest
		}
		writeJSON(w, status, map[string]string{"error": resp.Error})
		return
	}
	writeJSON(w, http.StatusOK, resp.Data)
}

func handleKeyEvent(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	var req Request
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "bad json"})
		return
	}
	req.Type = "keyevent"

	displayID := -1
	if req.Display != nil {
		displayID = *req.Display
	}
	resp := Dispatch(req)
	if !resp.OK {
		log.Printf("keyevent FAIL serial=%s key=%s display=%d err=%s", req.Serial, req.Key, displayID, resp.Error)
		status := http.StatusBadGateway
		if resp.Error == "missing serial" || resp.Error == ("unknown key: "+req.Key) {
			status = http.StatusBadRequest
		}
		writeJSON(w, status, map[string]string{"error": resp.Error})
		return
	}
	log.Printf("keyevent OK   serial=%s key=%s display=%d", req.Serial, req.Key, displayID)
	writeJSON(w, http.StatusOK, map[string]string{"ok": "1"})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
