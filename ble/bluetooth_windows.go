//go:build windows

// Package ble exposes a Bluetooth Classic SPP/RFCOMM listener for the dpadr server.
// On Windows it talks AF_BTH directly via Winsock; other platforms ship a no-op stub.
package ble

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"log"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

// Handler processes one newline-delimited JSON request line and returns a response
// payload (the bytes are sent back, followed by '\n'). The handler should never panic.
type Handler func(reqLine []byte) (respLine []byte)

// SPP service UUID — phones connect to this UUID, not a raw channel number.
// 00001101-0000-1000-8000-00805F9B34FB
var sppServiceClassID = windows.GUID{
	Data1: 0x00001101,
	Data2: 0x0000,
	Data3: 0x1000,
	Data4: [8]byte{0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB},
}

// Winsock + Bluetooth constants (ws2bth.h).
const (
	afBTH           = 32
	bthProtoRFCOMM  = 3
	sockStream      = 1
	sockaddrBTHSize = 30
	btPortAny       = 0

	rnrServiceRegister = 0
	nsBTH              = 16
)

var (
	modWS2_32          = windows.NewLazySystemDLL("ws2_32.dll")
	procWSASetServiceW = modWS2_32.NewProc("WSASetServiceW")
	procBind           = modWS2_32.NewProc("bind")
	procAccept         = modWS2_32.NewProc("accept")

	modKernel32       = windows.NewLazySystemDLL("kernel32.dll")
	procGetProcessHeap = modKernel32.NewProc("GetProcessHeap")
	procHeapAlloc      = modKernel32.NewProc("HeapAlloc")
	procHeapFree       = modKernel32.NewProc("HeapFree")
)

const heapZeroMemory = 0x00000008

// heapAlloc returns a process-heap pointer of `size` bytes, zeroed. The pointer
// is GC-stable (the GC has no idea this memory exists). Caller must heapFree it.
func heapAlloc(size uintptr) (uintptr, error) {
	hHeap, _, _ := procGetProcessHeap.Call()
	if hHeap == 0 {
		return 0, fmt.Errorf("GetProcessHeap returned 0")
	}
	p, _, e := procHeapAlloc.Call(hHeap, heapZeroMemory, size)
	if p == 0 {
		if e != nil {
			return 0, fmt.Errorf("HeapAlloc: %w", e)
		}
		return 0, fmt.Errorf("HeapAlloc returned 0")
	}
	return p, nil
}

func heapFree(p uintptr) {
	if p == 0 {
		return
	}
	hHeap, _, _ := procGetProcessHeap.Call()
	if hHeap == 0 {
		return
	}
	procHeapFree.Call(hHeap, 0, p)
}

// writeBytes copies src into the heap region at base+offset.
func writeBytes(base uintptr, offset uintptr, src []byte) {
	dst := unsafe.Slice((*byte)(unsafe.Pointer(base+offset)), len(src))
	copy(dst, src)
}

// writeUint32LE writes a 32-bit little-endian value to base+offset.
func writeUint32LE(base uintptr, offset uintptr, v uint32) {
	binary.LittleEndian.PutUint32(unsafe.Slice((*byte)(unsafe.Pointer(base+offset)), 4), v)
}

// writeUintptr writes a pointer-sized value to base+offset (host endianness).
func writeUintptr(base uintptr, offset uintptr, v uintptr) {
	*(*uintptr)(unsafe.Pointer(base + offset)) = v
}

func makeSockaddrBTH(btAddr uint64, classID windows.GUID, port uint32) [sockaddrBTHSize]byte {
	var b [sockaddrBTHSize]byte
	binary.LittleEndian.PutUint16(b[0:2], afBTH)
	binary.LittleEndian.PutUint64(b[2:10], btAddr)
	binary.LittleEndian.PutUint32(b[10:14], classID.Data1)
	binary.LittleEndian.PutUint16(b[14:16], classID.Data2)
	binary.LittleEndian.PutUint16(b[16:18], classID.Data3)
	copy(b[18:26], classID.Data4[:])
	binary.LittleEndian.PutUint32(b[26:30], port)
	return b
}

func parseSockaddrBTHPort(b []byte) uint32 {
	if len(b) < sockaddrBTHSize {
		return 0
	}
	return binary.LittleEndian.Uint32(b[26:30])
}

// Start brings up an RFCOMM listener on AF_BTH and registers an SPP service record.
// It returns nil on success and a wrapped error otherwise. Caller may ignore the error
// and continue (HTTP-only mode) when no Bluetooth adapter is available.
func Start(h Handler) error {
	var wsaData windows.WSAData
	if err := windows.WSAStartup(uint32(0x0202), &wsaData); err != nil {
		return fmt.Errorf("WSAStartup: %w", err)
	}

	sock, err := windows.WSASocket(afBTH, sockStream, bthProtoRFCOMM, nil, 0, 0)
	if err != nil {
		return fmt.Errorf("WSASocket(AF_BTH) — no BT adapter or driver?: %w", err)
	}

	// On Windows AF_BTH, BT_PORT_ANY (0) at bind() doesn't reliably trigger an
	// auto-assigned RFCOMM channel — getsockname keeps returning 0 even after
	// listen(). Instead we try fixed channels 30 → 1 until one binds.
	var chosenPort uint32
	for try := uint32(30); try >= 1; try-- {
		sa := makeSockaddrBTH(0, windows.GUID{}, try)
		if err := bindRaw(sock, sa[:]); err == nil {
			chosenPort = try
			break
		}
	}
	if chosenPort == 0 {
		windows.Closesocket(sock)
		return fmt.Errorf("bind: no free RFCOMM channel in 1..30")
	}

	if err := windows.Listen(sock, 4); err != nil {
		windows.Closesocket(sock)
		return fmt.Errorf("listen: %w", err)
	}

	if err := registerSPPService(chosenPort); err != nil {
		log.Printf("bluetooth: warning — SDP registration failed: %v (clients may need raw channel %d)", err, chosenPort)
	} else {
		log.Printf("bluetooth: SPP service registered on RFCOMM channel %d", chosenPort)
	}

	go acceptLoop(sock, h)
	return nil
}

func bindRaw(s windows.Handle, sa []byte) error {
	r, _, e := syscall.SyscallN(
		procBind.Addr(),
		uintptr(s),
		uintptr(unsafe.Pointer(&sa[0])),
		uintptr(len(sa)),
	)
	if int32(r) == -1 {
		if e != 0 {
			return e
		}
		return fmt.Errorf("bind returned -1")
	}
	return nil
}


// registerSPPService publishes an SDP record so phones can resolve the SPP UUID
// to our RFCOMM channel. All structures handed to ws2_32!WSASetServiceW are
// allocated on the process heap (not Go heap) so the GC cannot move or free them
// before the syscall returns. We free everything afterwards.
func registerSPPService(port uint32) error {
	// Heap-allocate each of the four pieces of memory ws2_32 will read:
	//   1. SOCKADDR_BTH       (30 bytes, but allocate 32 to keep alignment safe)
	//   2. CSADDR_INFO        (struct with two SOCKET_ADDRESSes + 2 ints)
	//   3. service name (UTF-16, null-terminated)
	//   4. WSAQUERYSETW       (the whole queryset structure)
	// then point the WSAQUERYSETW fields at #1-#3 and pass &queryset to the call.

	const sockaddrBTHAlloc = 32

	saPtr, err := heapAlloc(sockaddrBTHAlloc)
	if err != nil {
		return err
	}
	defer heapFree(saPtr)

	// Fill SOCKADDR_BTH at saPtr.
	sa := makeSockaddrBTH(0, sppServiceClassID, port)
	writeBytes(saPtr, 0, sa[:])

	// CSADDR_INFO layout on x64:
	//   SOCKET_ADDRESS LocalAddr   { LPSOCKADDR(8) + INT(4) + pad(4) } = 16
	//   SOCKET_ADDRESS RemoteAddr  { LPSOCKADDR(8) + INT(4) + pad(4) } = 16
	//   INT iSocketType                                              =  4
	//   INT iProtocol                                                =  4
	// total = 40 bytes
	const (
		csAllocSize       = 40
		csLocalSockaddrPP = 0
		csLocalLength     = 8
		csRemoteSockaddrP = 16
		csRemoteLength    = 24
		csSocketType      = 32
		csProtocol        = 36
	)
	csPtr, err := heapAlloc(csAllocSize)
	if err != nil {
		return err
	}
	defer heapFree(csPtr)

	writeUintptr(csPtr, csLocalSockaddrPP, saPtr)
	writeUint32LE(csPtr, csLocalLength, sockaddrBTHSize)
	writeUintptr(csPtr, csRemoteSockaddrP, 0)
	writeUint32LE(csPtr, csRemoteLength, 0)
	writeUint32LE(csPtr, csSocketType, sockStream)
	writeUint32LE(csPtr, csProtocol, bthProtoRFCOMM)

	// Service name as null-terminated UTF-16.
	nameUtf16 := utf16FromString("dpadr")
	nameBytes := uint16SliceToBytes(nameUtf16)
	namePtr, err := heapAlloc(uintptr(len(nameBytes)))
	if err != nil {
		return err
	}
	defer heapFree(namePtr)
	writeBytes(namePtr, 0, nameBytes)

	// Service class GUID lives stably on the heap too.
	guidPtr, err := heapAlloc(unsafe.Sizeof(windows.GUID{}))
	if err != nil {
		return err
	}
	defer heapFree(guidPtr)
	*(*windows.GUID)(unsafe.Pointer(guidPtr)) = sppServiceClassID

	// WSAQUERYSETW layout on x64 (little-endian, natural alignment):
	//   DWORD   dwSize                  (offset 0,   size 4)
	//   pad                             (offset 4,   size 4)
	//   LPWSTR  lpszServiceInstanceName (offset 8,   size 8)
	//   LPGUID  lpServiceClassId        (offset 16,  size 8)
	//   LPWSAVERSION lpVersion          (offset 24,  size 8)
	//   LPWSTR  lpszComment             (offset 32,  size 8)
	//   DWORD   dwNameSpace             (offset 40,  size 4)
	//   pad                             (offset 44,  size 4)
	//   LPGUID  lpNSProviderId          (offset 48,  size 8)
	//   LPWSTR  lpszContext             (offset 56,  size 8)
	//   DWORD   dwNumberOfProtocols     (offset 64,  size 4)
	//   pad                             (offset 68,  size 4)
	//   LPAFPROTOCOLS lpafpProtocols    (offset 72,  size 8)
	//   LPWSTR  lpszQueryString         (offset 80,  size 8)
	//   DWORD   dwNumberOfCsAddrs       (offset 88,  size 4)
	//   pad                             (offset 92,  size 4)
	//   LPCSADDR_INFO lpcsaBuffer       (offset 96,  size 8)
	//   DWORD   dwOutputFlags           (offset 104, size 4)
	//   pad                             (offset 108, size 4)
	//   LPBLOB  lpBlob                  (offset 112, size 8)
	// total = 120 bytes
	const (
		qSize             = 120
		qOffSize          = 0
		qOffName          = 8
		qOffClassID       = 16
		qOffNameSpace     = 40
		qOffNumCsAddrs    = 88
		qOffCsaBuffer     = 96
	)
	qPtr, err := heapAlloc(qSize)
	if err != nil {
		return err
	}
	defer heapFree(qPtr)

	writeUint32LE(qPtr, qOffSize, qSize)
	writeUintptr(qPtr, qOffName, namePtr)
	writeUintptr(qPtr, qOffClassID, guidPtr)
	writeUint32LE(qPtr, qOffNameSpace, nsBTH)
	writeUint32LE(qPtr, qOffNumCsAddrs, 1)
	writeUintptr(qPtr, qOffCsaBuffer, csPtr)

	r, _, e := procWSASetServiceW.Call(
		qPtr,
		uintptr(rnrServiceRegister),
		0,
	)
	if int32(r) != 0 {
		if e != nil && e.Error() != "" && e.Error() != "The operation completed successfully." {
			return e
		}
		return fmt.Errorf("WSASetService returned %d", int32(r))
	}
	return nil
}

// utf16FromString returns a null-terminated UTF-16 representation of s.
func utf16FromString(s string) []uint16 {
	r, err := syscall.UTF16FromString(s)
	if err != nil {
		// UTF16FromString fails only on embedded NULs; service name is hardcoded so this can't happen.
		return []uint16{0}
	}
	return r
}

func uint16SliceToBytes(u []uint16) []byte {
	out := make([]byte, len(u)*2)
	for i, v := range u {
		binary.LittleEndian.PutUint16(out[i*2:], v)
	}
	return out
}

func acceptLoop(listener windows.Handle, h Handler) {
	defer windows.Closesocket(listener)
	log.Printf("bluetooth: listening for SPP connections")
	for {
		var clientSA [sockaddrBTHSize]byte
		clientLen := int32(sockaddrBTHSize)
		r, _, e := syscall.SyscallN(
			procAccept.Addr(),
			uintptr(listener),
			uintptr(unsafe.Pointer(&clientSA[0])),
			uintptr(unsafe.Pointer(&clientLen)),
		)
		if int32(r) == -1 {
			log.Printf("bluetooth: accept error: %v", e)
			return
		}
		client := windows.Handle(r)
		go handleConnection(client, h)
	}
}

type btConn struct{ h windows.Handle }

func (c *btConn) Read(p []byte) (int, error) {
	if len(p) == 0 {
		return 0, nil
	}
	var n uint32
	buf := windows.WSABuf{Len: uint32(len(p)), Buf: &p[0]}
	var flags uint32
	err := windows.WSARecv(c.h, &buf, 1, &n, &flags, nil, nil)
	if err != nil {
		return 0, err
	}
	if n == 0 {
		return 0, fmt.Errorf("EOF")
	}
	return int(n), nil
}

func (c *btConn) Write(p []byte) (int, error) {
	if len(p) == 0 {
		return 0, nil
	}
	var n uint32
	buf := windows.WSABuf{Len: uint32(len(p)), Buf: &p[0]}
	err := windows.WSASend(c.h, &buf, 1, &n, 0, nil, nil)
	if err != nil {
		return 0, err
	}
	return int(n), nil
}

func (c *btConn) Close() error { return windows.Closesocket(c.h) }

func handleConnection(h windows.Handle, hand Handler) {
	c := &btConn{h: h}
	defer c.Close()
	log.Printf("bluetooth: client connected")

	r := bufio.NewReader(c)
	w := bufio.NewWriter(c)

	for {
		line, err := r.ReadBytes('\n')
		if len(line) > 0 {
			out := hand(line)
			if out != nil {
				w.Write(out)
				w.WriteByte('\n')
				if ferr := w.Flush(); ferr != nil {
					log.Printf("bluetooth: write error: %v", ferr)
					return
				}
			}
		}
		if err != nil {
			log.Printf("bluetooth: client disconnected (%v)", err)
			return
		}
	}
}
