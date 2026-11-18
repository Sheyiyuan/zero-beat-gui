//go:build !windows

package runtime

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestAndroidSocketStartupFailureCanRetry(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "core.sock")
	if err := os.WriteFile(path, []byte("occupied"), 0600); err != nil {
		t.Fatal(err)
	}
	config, _ := json.Marshal(map[string]any{"data_dir": dir, "platform": "android", "lock": false})
	var body map[string]any
	if err := json.Unmarshal([]byte(Start(string(config))), &body); err != nil {
		t.Fatal(err)
	}
	if body["ok"] != false {
		t.Fatalf("unexpected startup: %v", body)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal([]byte(Start(string(config))), &body); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(Stop)
	if body["ok"] != true || body["port"] != float64(0) || body["socket_path"] != path {
		t.Fatalf("retry: %v", body)
	}
	Stop()
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("shutdown cleanup: %v", err)
	}
}
