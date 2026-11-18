package rpc

import (
	"sync"

	"github.com/sheyiyuan/zero-beat-core/session"
)

type queuedFrame struct {
	data []byte
	done chan error
}

// frameQueue is the single outbound writer queue. Capacity counts frames
// waiting to be written and the frame currently being written.
type frameQueue struct {
	mu       sync.Mutex
	cond     *sync.Cond
	items    []queuedFrame
	inflight int
	limit    int
	closed   bool
}

func newFrameQueue(limit int) *frameQueue {
	q := &frameQueue{limit: limit}
	q.cond = sync.NewCond(&q.mu)
	return q
}

func finishFrame(done chan error, err error) {
	if done == nil {
		return
	}
	select {
	case done <- err:
	default:
	}
}

func (q *frameQueue) push(data []byte, done chan error) bool {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.closed || len(q.items)+q.inflight >= q.limit {
		q.closed = true
		q.cond.Broadcast()
		return false
	}
	q.items = append(q.items, queuedFrame{data: data, done: done})
	q.cond.Signal()
	return true
}

func (q *frameQueue) pop() (queuedFrame, bool) {
	q.mu.Lock()
	defer q.mu.Unlock()
	for len(q.items) == 0 && !q.closed {
		q.cond.Wait()
	}
	if len(q.items) == 0 {
		return queuedFrame{}, false
	}
	item := q.items[0]
	copy(q.items, q.items[1:])
	q.items = q.items[:len(q.items)-1]
	q.inflight++
	return item, true
}

func (q *frameQueue) ack() {
	q.mu.Lock()
	if q.inflight > 0 {
		q.inflight--
	}
	q.mu.Unlock()
}

func (q *frameQueue) shutdown() {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.closed = true
	for i := range q.items {
		finishFrame(q.items[i].done, errClosed)
		q.items[i].done = nil
	}
	q.cond.Broadcast()
}

func (q *frameQueue) depth() int {
	q.mu.Lock()
	defer q.mu.Unlock()
	return len(q.items) + q.inflight
}

type eventItem struct {
	ev       session.EngineEvent
	position bool
	terminal bool
}

// eventQueue coalesces position reports and keeps them from jumping a later
// terminal event. Reliable events that do not fit report overflow.
type eventQueue struct {
	mu     sync.Mutex
	cond   *sync.Cond
	items  []eventItem
	limit  int
	closed bool
}

func newEventQueue(limit int) *eventQueue {
	q := &eventQueue{limit: limit}
	q.cond = sync.NewCond(&q.mu)
	return q
}

func (q *eventQueue) push(item eventItem) bool {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.closed {
		return false
	}
	if item.position {
		for i := len(q.items) - 1; i >= 0; i-- {
			prev := q.items[i]
			if prev.ev.PlaybackID != item.ev.PlaybackID {
				continue
			}
			if prev.terminal {
				return true
			}
			if prev.position {
				if item.ev.Seq >= prev.ev.Seq {
					q.items[i] = item
				}
				return true
			}
			break
		}
	}
	if item.terminal {
		for _, prev := range q.items {
			if prev.terminal && prev.ev.PlaybackID == item.ev.PlaybackID {
				return true
			}
		}
	}
	if len(q.items) >= q.limit {
		if item.position {
			return true
		}
		return false
	}
	q.items = append(q.items, item)
	q.cond.Signal()
	return true
}

func (q *eventQueue) pop() (eventItem, bool) {
	q.mu.Lock()
	defer q.mu.Unlock()
	for len(q.items) == 0 && !q.closed {
		q.cond.Wait()
	}
	if len(q.items) == 0 {
		return eventItem{}, false
	}
	item := q.items[0]
	copy(q.items, q.items[1:])
	q.items = q.items[:len(q.items)-1]
	return item, true
}

func (q *eventQueue) dropPending() {
	q.mu.Lock()
	q.items = nil
	q.mu.Unlock()
}

func (q *eventQueue) shutdown() {
	q.mu.Lock()
	q.closed = true
	q.cond.Broadcast()
	q.mu.Unlock()
}

func (q *eventQueue) snapshot() []eventItem {
	q.mu.Lock()
	defer q.mu.Unlock()
	out := make([]eventItem, len(q.items))
	copy(out, q.items)
	return out
}
