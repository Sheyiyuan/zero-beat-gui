//go:build linux && !android

package runtime

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
	"github.com/sheyiyuan/zero-beat-core/player"
)

// TestSystemMediaCycleModeCommand 走一遍真实 MPRIS 厂商接口 → 命令队列 →
// runtime 会话，确认“切换播放模式”不是只导出方法而没有接到播放器。
func TestSystemMediaCycleModeCommand(t *testing.T) {
	if _, err := dbus.SessionBus(); err != nil {
		t.Skip("没有可用的会话总线")
	}
	name := fmt.Sprintf("org.mpris.MediaPlayer2.zero.runtime%d", os.Getpid())
	t.Setenv("ZERO_MPRIS_NAME", name)
	raw := Start(`{"data_dir":"` + t.TempDir() + `","platform":"linux","lock":false}`)
	t.Cleanup(Stop)
	var body map[string]any
	if err := json.Unmarshal([]byte(raw), &body); err != nil || body["ok"] != true {
		t.Skipf("无法启动 runtime: %s", raw)
	}

	conn, err := dbus.SessionBus()
	if err != nil {
		t.Skipf("连接会话总线: %v", err)
	}
	defer conn.Close()
	obj := conn.Object(name, dbus.ObjectPath("/org/mpris/MediaPlayer2"))
	call := func() {
		t.Helper()
		if err := obj.Call("org.zero_beat.MediaPlayer2.Control.CyclePlaybackMode", 0).Err; err != nil {
			t.Fatalf("CyclePlaybackMode: %v", err)
		}
	}
	waitMode := func(want player.Mode) {
		t.Helper()
		deadline := time.Now().Add(2 * time.Second)
		for {
			if current != nil && current.sess.Snapshot().Player.Mode == want {
				return
			}
			if time.Now().After(deadline) {
				got := player.Mode(-1)
				if current != nil {
					got = current.sess.Snapshot().Player.Mode
				}
				t.Fatalf("播放模式 = %v，期望 %v", got, want)
			}
			time.Sleep(10 * time.Millisecond)
		}
	}

	// 默认列表循环 → 单曲循环 → 随机。
	call()
	waitMode(player.ModeLoopOne)
	call()
	waitMode(player.ModeShuffle)

	// Restart 在空队列上不改变模式；这里确认厂商方法已导出，且 runtime
	// 的命令循环接住它时不会 panic 或改坏当前模式。
	if err := obj.Call("org.zero_beat.MediaPlayer2.Control.Restart", 0).Err; err != nil {
		t.Fatalf("Restart: %v", err)
	}
	waitMode(player.ModeShuffle)
}
