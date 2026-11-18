package runtime

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestStartRejectsInvalidConfig(t *testing.T) {
	for _, raw := range []string{
		`{`,
		`{"platform":""}`,
		`{"data_dir":"","platform":"android","lock":false}`,
		`{"data_dir":"   ","platform":"android","lock":false}`,
	} {
		var body map[string]any
		if err := json.Unmarshal([]byte(Start(raw)), &body); err != nil {
			t.Fatal(err)
		}
		if body["ok"] != false || body["code"] != "invalid_config" {
			t.Fatalf("%s -> %#v", raw, body)
		}
	}
	Stop()
	Stop()
}

func TestStartJSONShape(t *testing.T) {
	dir := t.TempDir()
	raw := Start(`{"data_dir":"` + dir + `","platform":"linux","lock":false}`)
	t.Cleanup(Stop)
	var body map[string]any
	if err := json.Unmarshal([]byte(raw), &body); err != nil {
		t.Fatal(raw, err)
	}
	if body["ok"] != true {
		t.Fatalf("start failed: %s", raw)
	}
	if int(body["api"].(float64)) != 1 || int(body["repo"].(float64)) != 3 || body["version"] != "0.1.0-dev" {
		t.Fatalf("%s", raw)
	}
	token, _ := body["token"].(string)
	if len(token) != 32 || strings.Trim(token, "0123456789abcdef") != "" {
		t.Fatalf("token %q", token)
	}
	again := Start(`{"data_dir":"` + dir + `","platform":"linux","lock":false}`)
	var second map[string]any
	if err := json.Unmarshal([]byte(again), &second); err != nil {
		t.Fatal(err)
	}
	if second["ok"] != false || second["code"] != "already_running" {
		t.Fatalf("second start: %s", again)
	}
}
