//go:build !windows

package rpc

import (
	"bufio"
	"net"
	"os"
	"path/filepath"
	"testing"
)

func TestUnixTransportAuthenticationAndSocketOwnership(t *testing.T) {
	path := filepath.Join(t.TempDir(), "core.sock")
	// Simulate an unclean process exit leaving its socket behind.
	stale, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	stale.SetUnlinkOnClose(false)
	if err := stale.Close(); err != nil {
		t.Fatal(err)
	}
	srv, err := ServeUnix(newFake(), NewRemoteEngine(), testToken, path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(srv.Shutdown)
	if srv.Port() != 0 || srv.SocketPath() != path {
		t.Fatal("wrong endpoint")
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("socket permissions: %v, %v", info, err)
	}
	if other, err := ServeUnix(newFake(), nil, testToken, path); err == nil {
		other.Shutdown()
		t.Fatal("replaced a live listener")
	}
	dialUnix := func() *lineConn {
		conn, err := net.Dial("unix", path)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = conn.Close() })
		return &lineConn{conn: conn, r: bufio.NewReader(conn)}
	}
	bad := dialUnix()
	response := bad.call(t, 1, MethodHello, map[string]any{"token": "wrong", "api": APIVersion})
	if object(t, response["error"])["code"] != float64(CodeUnauthorized) {
		t.Fatal(response)
	}
	assertClosed(t, bad.conn)
	good := dialUnix()
	if response := good.hello(t); response["error"] != nil {
		t.Fatal(response)
	}
	if response := good.call(t, 3, MethodPlaylists, map[string]any{}); response["error"] != nil {
		t.Fatal(response)
	}
	srv.Shutdown()
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("socket remains after shutdown: %v", err)
	}
}

func TestUnixTransportDoesNotRemoveRegularFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "core.sock")
	if err := os.WriteFile(path, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if srv, err := ServeUnix(newFake(), nil, testToken, path); err == nil {
		srv.Shutdown()
		t.Fatal("overwrote regular file")
	}
	if got, err := os.ReadFile(path); err != nil || string(got) != "keep" {
		t.Fatalf("file changed: %q, %v", got, err)
	}
}
