// Package wire defines versioned, explicitly projected GUI data contracts.
// It deliberately does not define a Session, socket server, or RPC dispatcher.
package wire

// SchemaVersion changes when a wire shape becomes incompatible. It is separate
// from the application's version and the future RPC api negotiation.
const SchemaVersion = 1

// Decimal is a signed 64-bit integer encoded as a decimal string. This preserves
// identifiers and counters on every Dart target, including JavaScript.
type Decimal string

// Timestamp is UTC RFC3339 with millisecond precision; optional timestamps are
// pointers and encode as null when the core's time.Time is zero.
type Timestamp string

type SourceID string
type BrowseKind string
type PlaybackStatus string
type PlaybackMode string
type Quality string
type SyncBackend string
type PlaylistKind string

// Capability names are generated from the actual core constants; unknown bits
// are retained separately so a newer source cannot silently lose capabilities.
type SourceCapabilities struct {
	Names       []string `json:"names"`
	UnknownBits Decimal  `json:"unknown_bits"`
}

type SourceInfo struct {
	ID           SourceID           `json:"id"`
	Name         string             `json:"name"`
	Mark         string             `json:"mark"`
	Capabilities SourceCapabilities `json:"capabilities"`
	User         User               `json:"user"`
}

type User struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Avatar   string `json:"avatar"`
	LoggedIn bool   `json:"logged_in"`
}

type TrackRef struct {
	Source     SourceID `json:"source"`
	ExternalID string   `json:"external_id"`
	Page       int      `json:"page"`
	CID        Decimal  `json:"cid"`
}

type Track struct {
	ID         string   `json:"id"`
	Source     SourceID `json:"source"`
	ExternalID string   `json:"external_id"`
	Page       int      `json:"page"`
	CID        Decimal  `json:"cid"`
	Title      string   `json:"title"`
	Artist     string   `json:"artist"`
	Album      string   `json:"album"`
	DurationMS int64    `json:"duration_ms"`
	Cover      string   `json:"cover"`
}

type Song struct {
	ID         string     `json:"id"`
	Source     SourceID   `json:"source"`
	RemoteID   string     `json:"remote_id"`
	Page       int        `json:"page"`
	CID        Decimal    `json:"cid"`
	Title      string     `json:"title"`
	Artist     string     `json:"artist"`
	Album      string     `json:"album"`
	DurationMS int64      `json:"duration_ms"`
	Cover      string     `json:"cover"`
	AddedAt    *Timestamp `json:"added_at"`
}

type Candidate struct {
	Track Track   `json:"track"`
	Play  Decimal `json:"play"`
	VIP   bool    `json:"vip"`
}

type SearchPage struct {
	Candidates []Candidate `json:"candidates"`
	Page       int         `json:"page"`
	Pages      int         `json:"pages"`
}

type RelatedPage struct {
	Candidates []Candidate `json:"candidates"`
}

type Playlist struct {
	ID           string       `json:"id"`
	Source       SourceID     `json:"source"`
	Title        string       `json:"title"`
	Kind         PlaylistKind `json:"kind"`
	RemoteID     string       `json:"remote_id"`
	Count        int          `json:"count"`
	Frozen       bool         `json:"frozen"`
	SyncExcluded bool         `json:"sync_excluded"`
	RootPath     string       `json:"root_path"`
	ScanStatus   string       `json:"scan_status"`
	HasScanError bool         `json:"has_scan_error"`
	ScannedAt    *Timestamp   `json:"scanned_at"`
	CreatedAt    *Timestamp   `json:"created_at"`
}

type RemotePlaylist struct {
	ID       string   `json:"id"`
	Source   SourceID `json:"source"`
	RemoteID string   `json:"remote_id"`
	Title    string   `json:"title"`
	Count    int      `json:"count"`
}

type QueueSnapshot struct {
	IDs        []string `json:"ids"`
	Index      int      `json:"index"`
	PositionMS int64    `json:"position_ms"`
}

// PlaybackSnapshot projects player.State. request_id is the controller request
// number, NOT the future RPC request id or playback_id. The latter does not
// exist in today's core and must be added by the future session envelope.
type PlaybackSnapshot struct {
	Queue      []Song         `json:"queue"`
	Index      int            `json:"index"`
	Current    *Song          `json:"current"`
	State      PlaybackStatus `json:"state"`
	PositionMS int64          `json:"position_ms"`
	DurationMS int64          `json:"duration_ms"`
	Mode       PlaybackMode   `json:"mode"`
	Volume     float64        `json:"volume"`
	CompDB     float64        `json:"comp_db"`
	SongCompDB float64        `json:"song_comp_db"`
	AutoGain   bool           `json:"auto_gain"`
	Muted      bool           `json:"muted"`
	Awaiting   bool           `json:"awaiting"`
	RequestID  int            `json:"request_id"`
	SleepUntil *Timestamp     `json:"sleep_until"`
	Quality    Quality        `json:"quality"`
}

// StreamInfo is safe for presentation. It deliberately omits URL and headers.
type StreamInfo struct {
	Codec       string     `json:"codec"`
	DurationMS  int64      `json:"duration_ms"`
	ExpiresAt   *Timestamp `json:"expires_at"`
	Quality     string     `json:"quality"`
	ClipStartMS int64      `json:"clip_start_ms"`
	ClipEndMS   int64      `json:"clip_end_ms"`
}

// EngineStream belongs exclusively to the authenticated engine bridge. Never
// log it, persist it, or put it into a presentation state/provider. It is exported
// by a separate Dart library because URLs and headers can carry credentials.
type EngineStream struct {
	URL         string            `json:"url"`
	Headers     map[string]string `json:"headers"`
	Codec       string            `json:"codec"`
	DurationMS  int64             `json:"duration_ms"`
	ExpiresAt   *Timestamp        `json:"expires_at"`
	Quality     string            `json:"quality"`
	ClipStartMS int64             `json:"clip_start_ms"`
	ClipEndMS   int64             `json:"clip_end_ms"`
}

type LyricLine struct {
	StartMS     int64  `json:"start_ms"`
	Text        string `json:"text"`
	Translation string `json:"translation"`
}

type BrowseRef struct {
	Source SourceID   `json:"source"`
	Kind   BrowseKind `json:"kind"`
	ID     string     `json:"id"`
}

type BrowseEntry struct {
	Title    string     `json:"title"`
	Subtitle string     `json:"subtitle"`
	Ref      *BrowseRef `json:"ref"`
	Track    *Track     `json:"track"`
}

type BrowsePage struct {
	Title       string        `json:"title"`
	Description string        `json:"description"`
	Cover       string        `json:"cover"`
	Notice      string        `json:"notice"`
	Entries     []BrowseEntry `json:"entries"`
	Page        int           `json:"page"`
	HasMore     bool          `json:"has_more"`
}

type ProfileList struct {
	Entries []BrowseEntry `json:"entries"`
}

type Comment struct {
	ID         string     `json:"id"`
	Author     string     `json:"author"`
	AuthorRef  *BrowseRef `json:"author_ref"`
	Avatar     string     `json:"avatar"`
	Content    string     `json:"content"`
	Likes      Decimal    `json:"likes"`
	CreatedAt  *Timestamp `json:"created_at"`
	ReplyCount int        `json:"reply_count"`
}

type CommentPage struct {
	Comments []Comment `json:"comments"`
	Page     int       `json:"page"`
	HasMore  bool      `json:"has_more"`
	Notice   string    `json:"notice"`
}

// SyncConfig only exposes connection choices. Remote userinfo, URL query and
// fragment are stripped by FromSyncConfig; token/key/password never appear.
type SyncConfig struct {
	Backend      SyncBackend `json:"backend"`
	Remote       string      `json:"remote"`
	Branch       string      `json:"branch"`
	Auto         bool        `json:"auto"`
	SyncAccounts bool        `json:"sync_accounts"`
}

// SyncStatus intentionally omits raw LastError/AuthHint/Warnings: upstream
// errors can embed remotes and credentials. A future session must classify
// errors into safe messages before presenting them to the UI.
type SyncStatus struct {
	RequestedBackend SyncBackend `json:"requested_backend"`
	ActualBackend    SyncBackend `json:"actual_backend"`
	Configured       bool        `json:"configured"`
	Remote           string      `json:"remote"`
	Branch           string      `json:"branch"`
	Auto             bool        `json:"auto"`
	SyncAccounts     bool        `json:"sync_accounts"`
	KeyCached        bool        `json:"key_cached"`
	KeyMatchesRepo   bool        `json:"key_matches_repo"`
	KeyVersion       int         `json:"key_version"`
	LastSyncAt       *Timestamp  `json:"last_sync_at"`
	HasError         bool        `json:"has_error"`
	HasKeyIssue      bool        `json:"has_key_issue"`
	ConflictTx       string      `json:"conflict_tx"`
	Conflicts        int         `json:"conflicts"`
	WarningCount     int         `json:"warning_count"`
}

type BindingKind string
type BindingScope string

type Clip struct {
	StartMS int64 `json:"start_ms"`
	EndMS   int64 `json:"end_ms"`
}

type Preferences struct {
	Volume          float64      `json:"volume"`
	CompDB          float64      `json:"comp_db"`
	AutoGain        bool         `json:"auto_gain"`
	Quality         Quality      `json:"quality"`
	Mode            PlaybackMode `json:"mode"`
	PlayingPlaylist string       `json:"playing_playlist"`
	LocalFirst      bool         `json:"local_first"`
	Mouse           bool         `json:"mouse"`
}

type Download struct {
	SongID     string     `json:"song_id"`
	Path       string     `json:"path"`
	Size       Decimal    `json:"size"`
	Codec      string     `json:"codec"`
	DurationMS int64      `json:"duration_ms"`
	CreatedAt  *Timestamp `json:"created_at"`
}

type DownloadEntry struct {
	Download Download `json:"download"`
	Song     *Song    `json:"song"`
}

type DownloadProgress struct {
	Done  Decimal `json:"done"`
	Total Decimal `json:"total"`
}

type DownloadResult struct {
	Song     Song    `json:"song"`
	Path     string  `json:"path"`
	Size     Decimal `json:"size"`
	HasError bool    `json:"has_error"`
}

type LyricBinding struct {
	Kind       BindingKind `json:"kind"`
	Source     SourceID    `json:"source"`
	ExternalID string      `json:"external_id"`
	Page       int         `json:"page"`
	CID        Decimal     `json:"cid"`
	LRCLIBID   Decimal     `json:"lrclib_id"`
	Path       string      `json:"path"`
	SongID     string      `json:"song_id"`
	Title      string      `json:"title"`
	Artist     string      `json:"artist"`
	DurationMS int64       `json:"duration_ms"`
	OffsetMS   int64       `json:"offset_ms"`
	BoundAt    *Timestamp  `json:"bound_at"`
}

type SongAnnotation struct {
	SongID        string        `json:"song_id"`
	LyricOffsetMS int64         `json:"lyric_offset_ms"`
	CompDB        float64       `json:"comp_db"`
	ClipStartMS   int64         `json:"clip_start_ms"`
	ClipEndMS     int64         `json:"clip_end_ms"`
	LyricBind     *LyricBinding `json:"lyric_bind"`
}

type LyricsResult struct {
	Lines       []LyricLine   `json:"lines"`
	OffsetMS    int64         `json:"offset_ms"`
	OffsetKey   BindingScope  `json:"offset_key"`
	Source      string        `json:"source"`
	Bound       bool          `json:"bound"`
	Degraded    bool          `json:"degraded"`
	HasWarning  bool          `json:"has_warning"`
	Binding     *LyricBinding `json:"binding"`
	BindingKind BindingScope  `json:"binding_kind"`
}

type LyricCandidate struct {
	Kind       BindingKind `json:"kind"`
	Source     SourceID    `json:"source"`
	ExternalID string      `json:"external_id"`
	Page       int         `json:"page"`
	CID        Decimal     `json:"cid"`
	LRCLIBID   Decimal     `json:"lrclib_id"`
	Path       string      `json:"path"`
	SongID     string      `json:"song_id"`
	Title      string      `json:"title"`
	Artist     string      `json:"artist"`
	DurationMS int64       `json:"duration_ms"`
	HasSynced  bool        `json:"has_synced"`
	Known      bool        `json:"known"`
	Mark       string      `json:"mark"`
}

type LyricPreview struct {
	Lines   []LyricLine  `json:"lines"`
	Label   string       `json:"label"`
	Count   int          `json:"count"`
	Binding LyricBinding `json:"binding"`
}

type SearchResult struct {
	Candidates []Candidate `json:"candidates"`
	Pages      int         `json:"pages"`
	HasWarning bool        `json:"has_warning"`
}

type LibraryScan struct {
	Playlist     Playlist `json:"playlist"`
	Subdirs      int      `json:"subdirs"`
	Scanned      int      `json:"scanned"`
	Added        int      `json:"added"`
	Reused       int      `json:"reused"`
	Missing      int      `json:"missing"`
	WarningCount int      `json:"warning_count"`
}
