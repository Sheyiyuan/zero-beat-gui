package rpc

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"math"
	"strconv"
	"time"

	"github.com/sheyiyuan/zero-beat-core/session"
	"github.com/sheyiyuan/zero-beat-core/store"
	"github.com/sheyiyuan/zero-beat-gui/wire"
)

func (c *clientConn) handleFrame(frame []byte) {
	msg, err := parseInbound(frame)
	if err != nil {
		if errors.Is(err, errBadID) {
			c.replyParse(CodeInvalidRequest, "请求无效")
			return
		}
		c.replyParse(CodeParse, "无法解析请求")
		return
	}
	if msg.Method == "" {
		if msg.HasID {
			c.deliverResponse(msg)
		}
		return
	}
	if !msg.HasID {
		c.deliverNotification(msg)
		return
	}
	if msg.JSONRPC != Version || msg.ID%2 == 0 {
		c.reply(msg.ID, nil, errBody(CodeInvalidRequest, "请求无效", nil))
		return
	}
	go c.handleRequest(msg)
}

func (c *clientConn) replyParse(code int, message string) {
	body := []byte(`{"jsonrpc":"2.0","id":null,"error":{"code":` + itoa(code) + `,"message":"` + message + `","data":{}}}` + "\n")
	c.enqueue(body, nil)
}

func itoa(n int) string {
	return strconv.Itoa(n)
}

func (c *clientConn) deliverNotification(msg inbound) {
	if c.srv.engine == nil {
		return
	}
	item, ok := eventFromParams(msg.Method, msg.Params)
	if !ok {
		return
	}
	if !c.srv.engine.pushEvent(item) {
		c.close()
	}
}

func (c *clientConn) handleRequest(msg inbound) {
	defer func() {
		if rec := recover(); rec != nil {
			log.Printf("rpc: panic method=%s", msg.Method)
			c.reply(msg.ID, nil, errBody(CodeInternal, "内部错误", nil))
		}
	}()
	if msg.Method == MethodCancel {
		c.handleCancel(msg)
		return
	}
	if msg.Method == MethodQuit {
		c.finishQuit(msg.ID)
		return
	}
	timeout := CallTimeout
	if SlowMethods(msg.Method) {
		timeout = SlowTimeout
	}
	ctx, cancel := context.WithTimeout(c.ctx, timeout)
	defer cancel()
	c.track(msg.ID, cancel)
	defer c.untrack(msg.ID)
	result, err := c.dispatch(ctx, msg.Method, msg.Params)
	if err != nil {
		c.reply(msg.ID, nil, mapSessionErr(err))
		return
	}
	c.reply(msg.ID, result, nil)
}

func (c *clientConn) handleCancel(msg inbound) {
	var p struct {
		RPCID int64 `json:"rpc_id"`
	}
	if err := decodeParams(msg.Params, &p); err != nil || p.RPCID < 1 {
		c.reply(msg.ID, nil, errBody(CodeInvalidParams, "参数错误", nil))
		return
	}
	// Even ids belong to engine calls this process started. Do not cancel them.
	if p.RPCID%2 == 0 {
		c.reply(msg.ID, map[string]any{}, nil)
		return
	}
	c.mu.Lock()
	cancel := c.inflight[p.RPCID]
	c.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	c.reply(msg.ID, map[string]any{}, nil)
}

func (c *clientConn) dispatch(ctx context.Context, method string, params json.RawMessage) (any, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	switch method {
	case MethodPlaylists:
		return c.playlists(ctx)
	case MethodSongs:
		return c.songs(ctx, params)
	case MethodSearch:
		return c.search(ctx, params)
	case MethodOpenLink:
		return c.openLink(ctx, params)
	case MethodPlay:
		return c.play(ctx, params)
	case MethodToggle:
		accepted, err := c.srv.sess.Toggle(ctx)
		return acceptedJSON(accepted, err)
	case MethodPause:
		return empty(c.srv.sess.Pause(ctx))
	case MethodStop:
		return empty(c.srv.sess.Stop(ctx))
	case MethodResume:
		return empty(c.srv.sess.Resume(ctx))
	case MethodNext:
		accepted, err := c.srv.sess.Next(ctx)
		return acceptedJSON(accepted, err)
	case MethodPrev:
		accepted, err := c.srv.sess.Prev(ctx)
		return acceptedJSON(accepted, err)
	case MethodSeek:
		return c.seek(ctx, params)
	case MethodVolume:
		return c.volume(ctx, params)
	case MethodMode:
		return c.mode(ctx, params)
	case MethodEnqueue:
		return c.enqueueSong(ctx, params, false)
	case MethodInsertNext:
		return c.enqueueSong(ctx, params, true)
	case MethodQueueRemove:
		return c.queueRemove(ctx, params)
	case MethodQueueMove:
		return c.queueMove(ctx, params)
	case MethodQueueClear:
		return empty(c.srv.sess.ClearUpcoming(ctx))
	case MethodPlayerState:
		return playerJSON(c.srv.sess.Snapshot())
	default:
		return c.featureDispatch(ctx, method, params)
	}
}

var errMethod = errors.New("rpc: method")

func empty(err error) (any, error) {
	if err != nil {
		return nil, err
	}
	return map[string]any{}, nil
}

func decodeParams(raw json.RawMessage, dest any) error {
	if len(raw) == 0 || string(raw) == "null" {
		raw = []byte("{}")
	}
	return json.Unmarshal(raw, dest)
}

func (c *clientConn) playlists(ctx context.Context) (any, error) {
	list, warn, err := c.srv.sess.Playlists(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]wire.Playlist, 0, len(list))
	for _, item := range list {
		out = append(out, wire.FromPlaylist(item))
	}
	view := struct {
		Playlists []wire.Playlist `json:"playlists"`
		Warning   string          `json:"warning"`
	}{Playlists: out, Warning: warn}
	if _, err := wire.Marshal(view); err != nil {
		return nil, err
	}
	return view, nil
}

func (c *clientConn) songs(ctx context.Context, params json.RawMessage) (any, error) {
	var p struct {
		PlaylistID string `json:"playlist_id"`
		Offset     int    `json:"offset"`
		Limit      int    `json:"limit"`
	}
	if err := decodeParams(params, &p); err != nil || p.PlaylistID == "" {
		return nil, errParams
	}
	page, err := c.srv.sess.Songs(ctx, p.PlaylistID, p.Offset, p.Limit)
	if err != nil {
		return nil, err
	}
	songs := make([]wire.Song, 0, len(page.Songs))
	for _, song := range page.Songs {
		songs = append(songs, wire.FromSong(song))
	}
	view := struct {
		Songs  []wire.Song `json:"songs"`
		Total  int         `json:"total"`
		Offset int         `json:"offset"`
		Limit  int         `json:"limit"`
	}{songs, page.Total, page.Offset, page.Limit}
	if _, err := wire.Marshal(view); err != nil {
		return nil, err
	}
	return view, nil
}

func (c *clientConn) search(ctx context.Context, params json.RawMessage) (any, error) {
	var p struct {
		Keyword string `json:"keyword"`
		Page    int    `json:"page"`
		Source  string `json:"source"`
	}
	if err := decodeParams(params, &p); err != nil {
		return nil, errParams
	}
	hit, err := c.srv.sess.Search(ctx, p.Keyword, p.Page, p.Source)
	if err != nil {
		return nil, err
	}
	candidates := make([]wire.Candidate, 0, len(hit.Candidates))
	for _, item := range hit.Candidates {
		candidates = append(candidates, wire.FromCandidate(item))
	}
	view := struct {
		Candidates []wire.Candidate `json:"candidates"`
		Pages      int              `json:"pages"`
		HasWarning bool             `json:"has_warning"`
		Warning    string           `json:"warning"`
	}{candidates, hit.Pages, hit.Warning != "", hit.Warning}
	if _, err := wire.Marshal(view); err != nil {
		return nil, err
	}
	return view, nil
}

func (c *clientConn) openLink(ctx context.Context, params json.RawMessage) (any, error) {
	var p struct {
		Text string `json:"text"`
	}
	if err := decodeParams(params, &p); err != nil {
		return nil, errParams
	}
	link, err := c.srv.sess.OpenLink(ctx, p.Text)
	if err != nil {
		return nil, err
	}
	kind := string(link.Kind)
	if kind == "" {
		kind = string(session.LinkUnknown)
	}
	view := struct {
		Matched bool           `json:"matched"`
		Kind    string         `json:"kind"`
		Ref     *wire.TrackRef `json:"ref"`
		Song    *wire.Song     `json:"song"`
	}{Matched: link.Matched, Kind: kind}
	if link.Matched {
		ref := wire.FromRef(link.Ref)
		song := wire.FromSong(link.Song)
		view.Ref = &ref
		view.Song = &song
	}
	if _, err := wire.Marshal(view); err != nil {
		return nil, err
	}
	return view, nil
}

func (c *clientConn) play(ctx context.Context, params json.RawMessage) (any, error) {
	var p struct {
		SongID     string      `json:"song_id"`
		Song       *wire.Song  `json:"song"`
		Queue      []wire.Song `json:"queue"`
		QueueIndex *int        `json:"queue_index"`
		StartAtMS  int64       `json:"start_at_ms"`
	}
	if err := decodeParams(params, &p); err != nil {
		return nil, errParams
	}
	index := -1
	if p.QueueIndex != nil {
		index = *p.QueueIndex
	}
	in := session.PlayInput{
		SongID:     p.SongID,
		QueueIndex: index,
		StartAt:    time.Duration(p.StartAtMS) * time.Millisecond,
	}
	if p.Song != nil {
		song, err := songFromWire(*p.Song)
		if err != nil {
			return nil, err
		}
		in.Song = &song
	}
	if len(p.Queue) > 0 {
		in.Queue = make([]store.Song, 0, len(p.Queue))
		for _, item := range p.Queue {
			song, err := songFromWire(item)
			if err != nil {
				return nil, err
			}
			in.Queue = append(in.Queue, song)
		}
	}
	return acceptedJSON(c.srv.sess.Play(ctx, in))
}

func acceptedJSON(result session.Accepted, err error) (any, error) {
	if err != nil {
		return nil, err
	}
	return struct {
		RequestID int  `json:"request_id"`
		Started   bool `json:"started"`
	}{result.RequestID, result.Started}, nil
}

func (c *clientConn) finishQuit(id int64) {
	if err := c.srv.sess.Close(); err != nil {
		c.reply(id, nil, mapSessionErr(err))
		return
	}
	if err := c.replyFlush(id, map[string]any{}, nil); err != nil {
		return
	}
	c.srv.Shutdown()
}

func (c *clientConn) seek(ctx context.Context, params json.RawMessage) (any, error) {
	var p struct {
		PositionMS int64 `json:"position_ms"`
	}
	if err := decodeParams(params, &p); err != nil {
		return nil, errParams
	}
	return empty(c.srv.sess.SeekMS(ctx, p.PositionMS))
}

func (c *clientConn) volume(ctx context.Context, params json.RawMessage) (any, error) {
	var p struct {
		Volume float64 `json:"volume"`
	}
	if err := decodeParams(params, &p); err != nil || math.IsNaN(p.Volume) || math.IsInf(p.Volume, 0) {
		return nil, errParams
	}
	return empty(c.srv.sess.SetVolume(ctx, p.Volume))
}

func (c *clientConn) mode(ctx context.Context, params json.RawMessage) (any, error) {
	var p struct {
		Mode string `json:"mode"`
	}
	if err := decodeParams(params, &p); err != nil {
		return nil, errParams
	}
	mode, err := wire.PlaybackMode(p.Mode).Core()
	if err != nil {
		return nil, errParams
	}
	return empty(c.srv.sess.SetMode(ctx, mode))
}

func (c *clientConn) enqueueSong(ctx context.Context, params json.RawMessage, next bool) (any, error) {
	var p struct {
		Song wire.Song `json:"song"`
	}
	if err := decodeParams(params, &p); err != nil {
		return nil, errParams
	}
	song, err := songFromWire(p.Song)
	if err != nil {
		return nil, err
	}
	var index int
	if next {
		index, err = c.srv.sess.InsertNext(ctx, song)
	} else {
		index, err = c.srv.sess.Enqueue(ctx, song)
	}
	if err != nil {
		return nil, err
	}
	return struct {
		Index int `json:"index"`
	}{index}, nil
}

func (c *clientConn) queueRemove(ctx context.Context, params json.RawMessage) (any, error) {
	var p struct {
		Index int `json:"index"`
	}
	if err := decodeParams(params, &p); err != nil {
		return nil, errParams
	}
	return empty(c.srv.sess.RemoveAt(ctx, p.Index))
}

func (c *clientConn) queueMove(ctx context.Context, params json.RawMessage) (any, error) {
	var p struct {
		Index int `json:"index"`
		Delta int `json:"delta"`
	}
	if err := decodeParams(params, &p); err != nil {
		return nil, errParams
	}
	return empty(c.srv.sess.MoveAt(ctx, p.Index, p.Delta))
}

var errParams = errors.New("rpc: params")

func songFromWire(s wire.Song) (store.Song, error) {
	if s.DurationMS < 0 {
		return store.Song{}, errParams
	}
	var cid int64
	if s.CID != "" {
		n, err := strconv.ParseInt(string(s.CID), 10, 64)
		if err != nil || n < 0 || strconv.FormatInt(n, 10) != string(s.CID) {
			return store.Song{}, errParams
		}
		cid = n
	}
	var added time.Time
	if s.AddedAt != nil && *s.AddedAt != "" {
		t, err := time.Parse("2006-01-02T15:04:05.000Z", string(*s.AddedAt))
		if err != nil {
			return store.Song{}, errParams
		}
		added = t
	}
	return store.NormalizeSong(store.Song{
		ID:       s.ID,
		Source:   string(s.Source),
		RemoteID: s.RemoteID,
		Page:     s.Page,
		CID:      cid,
		Title:    s.Title,
		Artist:   s.Artist,
		Album:    s.Album,
		Duration: int(s.DurationMS / 1000),
		Cover:    s.Cover,
		AddedAt:  added,
	}), nil
}

func playerJSON(snap session.Snapshot) (any, error) {
	raw, err := wire.Marshal(wire.FromPlayer(snap.Player))
	if err != nil {
		return nil, err
	}
	var id *string
	if snap.PlaybackID != "" {
		s := snap.PlaybackID
		id = &s
	}
	return struct {
		PlaybackID    *string         `json:"playback_id"`
		PlayWhenReady bool            `json:"play_when_ready"`
		Notice        string          `json:"notice"`
		NoticeLevel   string          `json:"notice_level"`
		Snapshot      json.RawMessage `json:"snapshot"`
	}{id, snap.PlayWhenReady, snap.Notice, snap.NoticeLevel, raw}, nil
}

func mapSessionErr(err error) *errorBody {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, context.Canceled), errors.Is(err, context.DeadlineExceeded):
		return errBody(CodeCancelled, "已取消", nil)
	case errors.Is(err, session.ErrStalePlayback):
		return errBody(CodeStalePlayback, "播放代次已过期", map[string]any{"reason": "stale_playback"})
	case errors.Is(err, session.ErrClosed):
		return errBody(CodeClosed, "会话已关闭", nil)
	case errors.Is(err, session.ErrNotFound), errors.Is(err, errParams):
		return errBody(CodeInvalidParams, "参数错误", nil)
	case errors.Is(err, session.ErrUnsupported), errors.Is(err, errMethod):
		if errors.Is(err, errMethod) {
			return errBody(CodeMethodNotFound, "未知方法", nil)
		}
		return errBody(CodeUnavailable, "暂不支持", nil)
	default:
		var public featureError
		if errors.As(err, &public) {
			return errBody(CodeUnavailable, redact(public.Error()), nil)
		}
		log.Printf("rpc: call: %s", redact(err.Error()))
		return errBody(CodeInternal, "内部错误", nil)
	}
}
