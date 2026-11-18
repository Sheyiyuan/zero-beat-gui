package rpc

import (
	"context"
	"encoding/json"
	"errors"
	"sync"
	"time"

	"github.com/sheyiyuan/zero-beat-core/media"
	"github.com/sheyiyuan/zero-beat-core/session"
)

var errNoPlayback = errors.New("rpc: no playback")

// Transport is the authenticated control connection. RemoteEngine does not
// hold its lock across Call.
type Transport interface {
	Call(ctx context.Context, method string, params any, timeout time.Duration) (json.RawMessage, error)
}

// RemoteEngine implements session.Engine. Playback IDs come from the session.
type RemoteEngine struct {
	cacheMu  sync.Mutex
	transMu  sync.Mutex
	tr       Transport
	events   chan session.EngineEvent
	in       *eventQueue
	done     chan struct{}
	stopOnce sync.Once

	playbackID string
	volume     float64
	compDB     float64
	autoGain   bool
	loudnorm   bool
	position   time.Duration
	duration   time.Duration
	state      media.State
	stream     media.Stream
	gens       map[string]genState
}

type genState struct {
	lastSeq  uint64
	terminal bool
}

func NewRemoteEngine() *RemoteEngine {
	e := &RemoteEngine{
		events: make(chan session.EngineEvent, 32),
		in:     newEventQueue(ReliableQueue),
		done:   make(chan struct{}),
		volume: 0.8,
		state:  media.StateIdle,
		gens:   map[string]genState{},
	}
	go e.forward()
	return e
}

func (e *RemoteEngine) attach(tr Transport) {
	e.transMu.Lock()
	e.tr = tr
	e.transMu.Unlock()
}

func (e *RemoteEngine) detach(tr Transport) {
	e.transMu.Lock()
	same := e.tr == tr
	if same {
		e.tr = nil
	}
	e.transMu.Unlock()
	if same {
		e.in.dropPending()
	}
}

// Shutdown ends the event forwarder. It is safe to call more than once.
func (e *RemoteEngine) Shutdown() {
	e.stopOnce.Do(func() {
		close(e.done)
		e.in.shutdown()
	})
}

func (e *RemoteEngine) SetCapabilities(caps []string) {
	loudnorm := false
	for _, name := range caps {
		if name == "loudnorm" {
			loudnorm = true
		}
	}
	e.cacheMu.Lock()
	e.loudnorm = loudnorm
	e.cacheMu.Unlock()
}

func (e *RemoteEngine) Load(ctx context.Context, playbackID string, stream media.Stream, at time.Duration, intent session.PlayIntent) error {
	stream.Headers = cloneHeaders(stream.Headers)
	e.cacheMu.Lock()
	e.playbackID = playbackID
	e.stream = stream
	e.state = media.StateBuffering
	e.position = at
	if stream.DurationMS > 0 {
		e.duration = time.Duration(stream.DurationMS) * time.Millisecond
	}
	delete(e.gens, playbackID)
	volume, comp, gain := e.volume, e.compDB, e.autoGain
	e.cacheMu.Unlock()

	params := map[string]any{
		"playback_id":     playbackID,
		"url":             stream.URL,
		"headers":         stream.Headers,
		"codec":           stream.Codec,
		"duration_ms":     stream.DurationMS,
		"quality":         stream.Quality,
		"clip_start_ms":   stream.ClipStartMS,
		"clip_end_ms":     stream.ClipEndMS,
		"start_at_ms":     at.Milliseconds(),
		"play_when_ready": intent.PlayWhenReady,
		"volume":          volume,
		"comp_db":         comp,
		"auto_gain":       gain,
	}
	raw, err := e.call(ctx, MethodEngineLoad, params, CallTimeout)
	if err != nil {
		e.failLoad(playbackID)
		return err
	}
	var ack struct {
		Accepted   bool   `json:"accepted"`
		PlaybackID string `json:"playback_id"`
	}
	if jsonErr := json.Unmarshal(raw, &ack); jsonErr != nil || !ack.Accepted || (ack.PlaybackID != "" && ack.PlaybackID != playbackID) {
		e.failLoad(playbackID)
		return errors.New("engine rejected load")
	}
	return nil
}

func (e *RemoteEngine) failLoad(playbackID string) {
	e.cacheMu.Lock()
	defer e.cacheMu.Unlock()
	if e.playbackID == playbackID {
		e.playbackID = ""
		e.state = media.StateIdle
		e.stream = media.Stream{}
	}
}

func (e *RemoteEngine) Pause(ctx context.Context, playbackID string) error {
	return e.simple(ctx, MethodEnginePause, playbackID, nil)
}

func (e *RemoteEngine) Resume(ctx context.Context, playbackID string) error {
	return e.simple(ctx, MethodEngineResume, playbackID, nil)
}

func (e *RemoteEngine) Stop(ctx context.Context, playbackID string) error {
	return e.simple(ctx, MethodEngineStop, playbackID, nil)
}

func (e *RemoteEngine) Seek(ctx context.Context, playbackID string, at time.Duration) error {
	return e.simple(ctx, MethodEngineSeek, playbackID, map[string]any{"position_ms": at.Milliseconds()})
}

func (e *RemoteEngine) SetVolume(ctx context.Context, playbackID string, volume float64) error {
	e.cacheMu.Lock()
	e.volume = volume
	current := e.playbackID
	e.cacheMu.Unlock()
	if current == "" {
		return nil
	}
	if playbackID != current {
		return session.ErrStalePlayback
	}
	_, err := e.call(ctx, MethodEngineVolume, map[string]any{"playback_id": current, "volume": volume}, CallTimeout)
	return err
}

func (e *RemoteEngine) SetCompensationDB(ctx context.Context, playbackID string, db float64) error {
	e.cacheMu.Lock()
	e.compDB = db
	current := e.playbackID
	e.cacheMu.Unlock()
	if current == "" {
		return nil
	}
	if playbackID != current {
		return session.ErrStalePlayback
	}
	_, err := e.call(ctx, MethodEngineComp, map[string]any{"playback_id": current, "comp_db": db}, CallTimeout)
	return err
}

func (e *RemoteEngine) SetAutoGain(ctx context.Context, playbackID string, on bool) error {
	e.cacheMu.Lock()
	e.autoGain = on
	current := e.playbackID
	e.cacheMu.Unlock()
	if current == "" {
		return nil
	}
	if playbackID != current {
		return session.ErrStalePlayback
	}
	_, err := e.call(ctx, MethodEngineAutoGain, map[string]any{"playback_id": current, "enabled": on}, CallTimeout)
	return err
}

func (e *RemoteEngine) simple(ctx context.Context, method, playbackID string, extra map[string]any) error {
	if err := e.match(playbackID); err != nil {
		if errors.Is(err, errNoPlayback) {
			return nil
		}
		return err
	}
	params := map[string]any{"playback_id": playbackID}
	for k, v := range extra {
		params[k] = v
	}
	_, err := e.call(ctx, method, params, CallTimeout)
	return err
}

func (e *RemoteEngine) match(playbackID string) error {
	e.cacheMu.Lock()
	current := e.playbackID
	e.cacheMu.Unlock()
	if current == "" || playbackID == "" {
		return errNoPlayback
	}
	if playbackID != current {
		return session.ErrStalePlayback
	}
	return nil
}

func (e *RemoteEngine) call(ctx context.Context, method string, params any, timeout time.Duration) (json.RawMessage, error) {
	e.transMu.Lock()
	tr := e.tr
	e.transMu.Unlock()
	if tr == nil {
		return nil, errClosed
	}
	raw, err := tr.Call(ctx, method, params, timeout)
	if err != nil {
		var body *errorBody
		if errors.As(err, &body) && (body.Code == CodeStalePlayback || staleReason(body.Data)) {
			return nil, session.ErrStalePlayback
		}
		return nil, err
	}
	return raw, nil
}

func (e *RemoteEngine) AutoGainSupported() bool {
	e.cacheMu.Lock()
	defer e.cacheMu.Unlock()
	return e.loudnorm
}

func (e *RemoteEngine) Position() time.Duration {
	e.cacheMu.Lock()
	defer e.cacheMu.Unlock()
	return e.position
}

func (e *RemoteEngine) Duration() time.Duration {
	e.cacheMu.Lock()
	defer e.cacheMu.Unlock()
	return e.duration
}

func (e *RemoteEngine) State() media.State {
	e.cacheMu.Lock()
	defer e.cacheMu.Unlock()
	return e.state
}

func (e *RemoteEngine) CurrentStream() media.Stream {
	e.cacheMu.Lock()
	defer e.cacheMu.Unlock()
	out := e.stream
	out.Headers = cloneHeaders(e.stream.Headers)
	return out
}

func (e *RemoteEngine) Events() <-chan session.EngineEvent { return e.events }

func (e *RemoteEngine) pushEvent(item eventItem) bool {
	return e.in.push(item)
}

func (e *RemoteEngine) forward() {
	for {
		item, ok := e.in.pop()
		if !ok {
			return
		}
		if !e.apply(item) {
			continue
		}
		if item.position {
			continue
		}
		select {
		case e.events <- item.ev:
		case <-e.done:
			return
		}
	}
}

func (e *RemoteEngine) apply(item eventItem) bool {
	e.cacheMu.Lock()
	defer e.cacheMu.Unlock()
	id := item.ev.PlaybackID
	if id == "" || id != e.playbackID {
		return false
	}
	gen := e.gens[id]
	if gen.terminal {
		return false
	}
	if item.ev.Seq > 0 && item.ev.Seq <= gen.lastSeq {
		return false
	}
	if item.ev.Seq > 0 {
		gen.lastSeq = item.ev.Seq
	}
	e.position = item.ev.Position
	if item.ev.Duration > 0 {
		e.duration = item.ev.Duration
	}
	switch {
	case item.terminal && item.ev.Type == media.EventFailed:
		e.state = media.StateFailed
		gen.terminal = true
	case item.terminal:
		e.state = media.StateEnded
		gen.terminal = true
	case item.position:
	default:
		e.state = item.ev.State
	}
	e.gens[id] = gen
	return true
}

func cloneHeaders(in map[string]string) map[string]string {
	out := make(map[string]string, len(in))
	for k, v := range in {
		out[k] = v
	}
	return out
}

func eventFromParams(method string, params json.RawMessage) (eventItem, bool) {
	var p struct {
		PlaybackID string `json:"playback_id"`
		Seq        uint64 `json:"seq"`
		State      string `json:"state"`
		PositionMS int64  `json:"position_ms"`
		DurationMS int64  `json:"duration_ms"`
		Error      string `json:"error"`
	}
	if len(params) > 0 && string(params) != "null" {
		if err := json.Unmarshal(params, &p); err != nil {
			return eventItem{}, false
		}
	}
	ev := session.EngineEvent{
		PlaybackID: p.PlaybackID,
		Seq:        p.Seq,
		Position:   time.Duration(p.PositionMS) * time.Millisecond,
		Duration:   time.Duration(p.DurationMS) * time.Millisecond,
		State:      mediaState(p.State),
	}
	item := eventItem{ev: ev}
	switch method {
	case EventEnginePosition:
		item.position = true
	case EventEnginePlaying:
		ev.Type = media.EventStateChanged
		item.ev = ev
	case EventEngineEnded:
		ev.Type = media.EventEnded
		ev.State = media.StateEnded
		item.ev = ev
		item.terminal = true
	case EventEngineFailed:
		ev.Type = media.EventFailed
		ev.State = media.StateFailed
		if p.Error != "" {
			ev.Err = errors.New(redact(p.Error))
		}
		item.ev = ev
		item.terminal = true
	default:
		return eventItem{}, false
	}
	return item, true
}

func mediaState(name string) media.State {
	switch name {
	case "buffering":
		return media.StateBuffering
	case "playing":
		return media.StatePlaying
	case "paused":
		return media.StatePaused
	case "ended":
		return media.StateEnded
	case "failed":
		return media.StateFailed
	default:
		return media.StateIdle
	}
}
