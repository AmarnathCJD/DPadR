package main

import (
	"fmt"
	"io"
	"net"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const adbServerAddr = "127.0.0.1:5037"

type Device struct {
	Serial string `json:"serial"`
	State  string `json:"state"`
}

func dial() (net.Conn, error) {
	return net.DialTimeout("tcp", adbServerAddr, 2*time.Second)
}

func sendRequest(conn net.Conn, payload string) error {
	frame := fmt.Sprintf("%04x%s", len(payload), payload)
	if _, err := conn.Write([]byte(frame)); err != nil {
		return fmt.Errorf("write request: %w", err)
	}
	return readStatus(conn)
}

func readStatus(conn net.Conn) error {
	buf := make([]byte, 4)
	if _, err := io.ReadFull(conn, buf); err != nil {
		return fmt.Errorf("read status: %w", err)
	}
	switch string(buf) {
	case "OKAY":
		return nil
	case "FAIL":
		msg, _ := readLengthPrefixed(conn)
		return fmt.Errorf("adb FAIL: %s", msg)
	default:
		return fmt.Errorf("unexpected status: %q", string(buf))
	}
}

func readLengthPrefixed(conn net.Conn) (string, error) {
	lenBuf := make([]byte, 4)
	if _, err := io.ReadFull(conn, lenBuf); err != nil {
		return "", err
	}
	size := 0
	if _, err := fmt.Sscanf(string(lenBuf), "%04x", &size); err != nil {
		return "", fmt.Errorf("bad length prefix %q: %w", string(lenBuf), err)
	}
	if size == 0 {
		return "", nil
	}
	body := make([]byte, size)
	if _, err := io.ReadFull(conn, body); err != nil {
		return "", err
	}
	return string(body), nil
}

func ListDevices() ([]Device, error) {
	conn, err := dial()
	if err != nil {
		return nil, fmt.Errorf("dial adb-server: %w (is `adb start-server` running?)", err)
	}
	defer conn.Close()

	conn.SetDeadline(time.Now().Add(3 * time.Second))

	if err := sendRequest(conn, "host:devices"); err != nil {
		return nil, err
	}
	body, err := readLengthPrefixed(conn)
	if err != nil {
		return nil, err
	}

	var devices []Device
	for _, line := range strings.Split(strings.TrimSpace(body), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) < 2 {
			continue
		}
		devices = append(devices, Device{Serial: parts[0], State: parts[1]})
	}
	return devices, nil
}

type Display struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

// runShell executes a shell command on the given device and returns combined output.
func runShell(serial, cmd string, timeout time.Duration) (string, error) {
	conn, err := dial()
	if err != nil {
		return "", fmt.Errorf("dial adb-server: %w", err)
	}
	defer conn.Close()

	conn.SetDeadline(time.Now().Add(timeout))

	if err := sendRequest(conn, "host:transport:"+serial); err != nil {
		return "", fmt.Errorf("transport: %w", err)
	}
	if err := sendRequest(conn, "shell:"+cmd); err != nil {
		return "", fmt.Errorf("shell: %w", err)
	}
	out, err := io.ReadAll(conn)
	if err != nil {
		return "", err
	}
	return string(out), nil
}

func SendKeyEvent(serial string, keycode int, displayID int) error {
	cmd := fmt.Sprintf("input keyevent %d", keycode)
	if displayID >= 0 {
		cmd = fmt.Sprintf("input -d %d keyevent %d", displayID, keycode)
	}
	_, err := runShell(serial, cmd, 5*time.Second)
	return err
}

// ListDisplays parses `dumpsys display` output for logical display IDs.
// We look at the "mDisplayStates=" array which lists each logical display id,
// then mirror to the per-display blocks for friendly names.
func ListDisplays(serial string) ([]Display, error) {
	out, err := runShell(serial, "dumpsys display", 5*time.Second)
	if err != nil {
		return nil, err
	}

	// Each logical display block looks like:
	//   Display Device: ...
	//     mDisplayId=0
	//     ...
	//     mDisplayInfoInternal=DisplayInfo{"<name>", ...
	// We pair an id with the closest preceding "Display Device:" name when present.
	idRe := regexp.MustCompile(`(?m)^\s*mDisplayId=(\d+)`)
	nameRe := regexp.MustCompile(`(?m)^\s*Display Device:\s*"?([^"\n]+?)"?\s*$`)

	type pos struct {
		id   int
		off  int
	}
	var ids []pos
	for _, m := range idRe.FindAllStringSubmatchIndex(out, -1) {
		idStr := out[m[2]:m[3]]
		id, err := strconv.Atoi(idStr)
		if err != nil {
			continue
		}
		ids = append(ids, pos{id: id, off: m[0]})
	}

	type namePos struct {
		name string
		off  int
	}
	var names []namePos
	for _, m := range nameRe.FindAllStringSubmatchIndex(out, -1) {
		names = append(names, namePos{name: strings.TrimSpace(out[m[2]:m[3]]), off: m[0]})
	}

	seen := map[int]bool{}
	var displays []Display
	for _, p := range ids {
		if seen[p.id] {
			continue
		}
		seen[p.id] = true
		// pick the most recent Display Device: name before this id
		name := ""
		for _, n := range names {
			if n.off < p.off {
				name = n.name
			} else {
				break
			}
		}
		if name == "" {
			name = fmt.Sprintf("Display %d", p.id)
		}
		displays = append(displays, Display{ID: p.id, Name: name})
	}

	return displays, nil
}

