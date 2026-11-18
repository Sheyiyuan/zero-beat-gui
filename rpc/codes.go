// Package rpc 是 GUI 首批本机 JSON-RPC 契约。
//
// 传输、连接所有权和 RemoteEngine 由本模块其余文件实现。
// 这里的方法名、错误码和超时是跨语言样本的稳定部分，不要改名。
package rpc

import (
	"strings"
	"time"
)

const (
	Version         = "2.0"
	APIVersion      = 1
	RepoVersion     = 3
	GUIVersion      = "0.1.0-dev"
	MaxFrame        = 8 << 20
	MaxHelloFrame   = 16 << 10
	MaxPendingHello = 8
	HelloTimeout    = 3 * time.Second
	CallTimeout     = 3 * time.Second
	SlowTimeout     = 20 * time.Second
	ReadyTimeout    = 20 * time.Second
	SlowNotice      = 5 * time.Second
	ReliableQueue   = 64
)

const (
	CodeParse          = -32700
	CodeInvalidRequest = -32600
	CodeMethodNotFound = -32601
	CodeInvalidParams  = -32602
	CodeInternal       = -32603
	CodeUnauthorized   = -32001
	CodeVersion        = -32002
	CodeCancelled      = -32004
	CodeUnavailable    = -32010
	CodeStalePlayback  = -32011
	CodeClosed         = -32012
)

const (
	MethodHello          = "core.hello"
	MethodCancel         = "core.cancel"
	MethodPlaylists      = "library.playlists"
	MethodSongs          = "library.songs"
	MethodSearch         = "search.query"
	MethodOpenLink       = "source.open_link"
	MethodPlay           = "player.play"
	MethodToggle         = "player.toggle"
	MethodPause          = "player.pause"
	MethodStop           = "player.stop"
	MethodResume         = "player.resume"
	MethodNext           = "player.next"
	MethodPrev           = "player.prev"
	MethodSeek           = "player.seek"
	MethodVolume         = "player.volume"
	MethodMode           = "player.mode"
	MethodEnqueue        = "player.enqueue"
	MethodInsertNext     = "player.insert_next"
	MethodQueueRemove    = "player.queue_remove"
	MethodQueueMove      = "player.queue_move"
	MethodQueueClear     = "player.queue_clear"
	MethodPlayerState    = "player.state"
	MethodQuit           = "app.quit"
	MethodEngineLoad     = "engine.load"
	MethodEnginePause    = "engine.pause"
	MethodEngineResume   = "engine.resume"
	MethodEngineStop     = "engine.stop"
	MethodEngineSeek     = "engine.seek"
	MethodEngineVolume   = "engine.volume"
	MethodEngineComp     = "engine.comp"
	MethodEngineAutoGain = "engine.auto_gain"
	MethodEngineState    = "engine.state"
	EventPlayerState     = "player.state"
	EventEnginePosition  = "engine.position"
	EventEnginePlaying   = "engine.state"
	EventEngineEnded     = "engine.ended"
	EventEngineFailed    = "engine.failed"
	EventNotice          = "notice"
)

// SlowMethods 使用 20 秒超时，其余业务方法 3 秒。
func SlowMethods(method string) bool {
	for _, prefix := range []string{"auth.", "content.", "browse.", "lyrics.", "library.", "search.", "download.", "sync.", "tasks."} {
		if strings.HasPrefix(method, prefix) {
			return true
		}
	}
	switch method {
	case MethodSearch, MethodOpenLink, MethodSongs, MethodPlaylists:
		return true
	default:
		return false
	}
}

// ImplementedCapabilities 只声明本批已经实现的能力。
func ImplementedCapabilities(engine []string) []string {
	return implementedCapabilities(engine, true)
}

func implementedCapabilities(engine []string, features bool) []string {
	out := []string{"library", "search", "link", "player"}
	if features {
		out = append(out, "auth", "content", "browse", "lyrics", "settings", "batch", "download", "sync", "tasks", "resource")
	}
	for _, name := range engine {
		if name == "loudnorm" || name == "clip" {
			out = append(out, name)
		}
	}
	return out
}
