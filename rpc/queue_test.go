package rpc

import (
	"testing"
	"time"

	"github.com/sheyiyuan/zero-beat-core/media"
	"github.com/sheyiyuan/zero-beat-core/session"
)

func TestFrameQueueRejectsPastCapacity(t *testing.T) {
	q := newFrameQueue(ReliableQueue)
	for i := 0; i < ReliableQueue; i++ {
		if !q.push([]byte{byte(i)}, nil) {
			t.Fatalf("push %d", i)
		}
	}
	if q.push([]byte("overflow"), nil) {
		t.Fatal("reliable frame past capacity was accepted")
	}
	if q.depth() != ReliableQueue {
		t.Fatalf("depth %d", q.depth())
	}
}

func TestPositionCoalesceStaysBeforeTerminal(t *testing.T) {
	q := newEventQueue(8)
	pos := func(seq uint64, ms int64) eventItem {
		return eventItem{
			position: true,
			ev: session.EngineEvent{
				PlaybackID: "pb_01",
				Seq:        seq,
				Position:   time.Duration(ms) * time.Millisecond,
			},
		}
	}
	if !q.push(pos(1, 1000)) || !q.push(pos(2, 2000)) {
		t.Fatal("position")
	}
	ended := eventItem{terminal: true, ev: session.EngineEvent{
		PlaybackID: "pb_01", Seq: 3, Type: media.EventEnded, State: media.StateEnded,
		Position: 245 * time.Second,
	}}
	if !q.push(ended) {
		t.Fatal("ended")
	}
	if !q.push(pos(4, 9999)) {
		t.Fatal("late position should be ignored, not overflow")
	}
	got := q.snapshot()
	if len(got) != 2 {
		t.Fatalf("len %d", len(got))
	}
	if !got[0].position || got[0].ev.Seq != 2 || got[0].ev.Position != 2000*time.Millisecond {
		t.Fatalf("coalesced position %+v", got[0])
	}
	if !got[1].terminal || got[1].ev.Seq != 3 {
		t.Fatalf("terminal moved: %+v", got[1])
	}
}

func TestReliableEventsDoNotFitSilently(t *testing.T) {
	q := newEventQueue(2)
	state := func(seq uint64) eventItem {
		return eventItem{ev: session.EngineEvent{PlaybackID: "pb", Seq: seq, Type: media.EventStateChanged, State: media.StatePlaying}}
	}
	if !q.push(state(1)) || !q.push(state(2)) {
		t.Fatal("state")
	}
	if q.push(state(3)) {
		t.Fatal("third state was dropped silently")
	}
	if !q.push(eventItem{position: true, ev: session.EngineEvent{PlaybackID: "pb", Seq: 4}}) {
		t.Fatal("a position may be coalesced or dropped without closing")
	}
	if len(q.snapshot()) != 2 {
		t.Fatalf("position overwritten a full reliable queue: %+v", q.snapshot())
	}
}
