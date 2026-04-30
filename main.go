package main

import (
	"embed"
	"encoding/json"
	"flag"
	"io/fs"
	"log"
	"net/http"
)

//go:embed static
var staticFS embed.FS

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
	flag.Parse()

	sub, err := fs.Sub(staticFS, "static")
	if err != nil {
		log.Fatalf("embed sub: %v", err)
	}

	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.FS(sub)))
	mux.HandleFunc("/api/devices", handleDevices)
	mux.HandleFunc("/api/displays", handleDisplays)
	mux.HandleFunc("/api/keyevent", handleKeyEvent)

	log.Printf("listening on http://%s", *addr)
	if err := http.ListenAndServe(*addr, mux); err != nil {
		log.Fatal(err)
	}
}

func handleDevices(w http.ResponseWriter, r *http.Request) {
	devices, err := ListDevices()
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	if devices == nil {
		devices = []Device{}
	}
	writeJSON(w, http.StatusOK, devices)
}

func handleDisplays(w http.ResponseWriter, r *http.Request) {
	serial := r.URL.Query().Get("serial")
	if serial == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing serial"})
		return
	}
	displays, err := ListDisplays(serial)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	if displays == nil {
		displays = []Display{}
	}
	writeJSON(w, http.StatusOK, displays)
}

func handleKeyEvent(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		Serial  string `json:"serial"`
		Key     string `json:"key"`
		Display *int   `json:"display,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "bad json"})
		return
	}
	if req.Serial == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing serial"})
		return
	}
	code, ok := keyMap[req.Key]
	if !ok {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unknown key: " + req.Key})
		return
	}

	displayID := -1
	if req.Display != nil {
		displayID = *req.Display
	}

	if err := SendKeyEvent(req.Serial, code, displayID); err != nil {
		log.Printf("keyevent FAIL serial=%s key=%s code=%d display=%d err=%v", req.Serial, req.Key, code, displayID, err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	log.Printf("keyevent OK   serial=%s key=%s code=%d display=%d", req.Serial, req.Key, code, displayID)
	writeJSON(w, http.StatusOK, map[string]string{"ok": "1"})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
