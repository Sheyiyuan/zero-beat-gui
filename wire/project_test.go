package wire

import (
	"encoding/json"
	"github.com/sheyiyuan/zero-beat-core/media"
	"github.com/sheyiyuan/zero-beat-core/player"
	"github.com/sheyiyuan/zero-beat-core/source"
	"github.com/sheyiyuan/zero-beat-core/store"
	coresync "github.com/sheyiyuan/zero-beat-core/sync"
	"math"
	"strings"
	"testing"
	"time"
)

func TestCoreFixturesCoverAllDTOs(t *testing.T) {
	seen := map[string]bool{}
	for _, f := range Fixtures() {
		t.Run(f.Name, func(t *testing.T) {
			seen[f.Type] = true
			b, err := Marshal(f.Value)
			if err != nil {
				t.Fatal(err)
			}
			if !json.Valid(b) {
				t.Fatal("invalid JSON")
			}
		})
	}
	for _, typ := range Types {
		if !seen[typ.Name()] {
			t.Errorf("no core fixture for %s", typ.Name())
		}
	}
}
func TestProgramAndLegacySongIdentity(t *testing.T) {
	program := FromTrack(source.Track{Source: source.NetEase, ExternalID: "program:2066770638", Duration: 245})
	if program.ID != "netease:program:2066770638:1" || program.ExternalID != "program:2066770638" || program.DurationMS != 245000 {
		t.Fatalf("program identity/unit corrupted: %+v", program)
	}
	legacy := FromSong(store.Song{Source: "bilibili", BVID: "BV1legacy", CID: math.MaxInt64})
	if legacy.ID != "bilibili:BV1legacy:1" || legacy.RemoteID != "BV1legacy" || legacy.CID != "9223372036854775807" || legacy.AddedAt != nil {
		t.Fatalf("legacy normalization: %+v", legacy)
	}
}
func TestTimeUnitsAndNullable(t *testing.T) {
	now := time.Date(2026, 11, 17, 8, 9, 10, 123456789, time.FixedZone("UTC+8", 28800))
	s := FromSong(store.Song{AddedAt: now})
	if string(*s.AddedAt) != "2026-11-17T00:09:10.123Z" {
		t.Fatal(*s.AddedAt)
	}
	p := FromPlayer(player.State{Position: 1234567 * time.Microsecond, Duration: 2 * time.Second})
	if p.PositionMS != 1234 || p.DurationMS != 2000 || p.Current != nil || p.SleepUntil != nil || p.Queue == nil {
		t.Fatalf("player units/null: %+v", p)
	}
	if FromQueue(store.QueueState{Position: 1234}).PositionMS != 1234 {
		t.Fatal("queue ms was scaled")
	}
	if FromPlaylist(store.Playlist{CreatedAt: now.Unix()}).CreatedAt == nil {
		t.Fatal("Unix seconds omitted")
	}
}
func TestEnumAndCapabilityForwardCompatibility(t *testing.T) {
	p := FromPlayer(player.State{PlaybackState: media.State(99), Mode: player.Mode(99), Quality: source.Quality(99)})
	if p.State != "unknown:99" || p.Mode != "unknown:99" || p.Quality != "unknown:99" {
		t.Fatal(p)
	}
	c := FromCapabilities(source.CapComments | source.CapRelated | source.CapBrowse | source.Capability(1<<31))
	if strings.Join(c.Names, ",") != "comments,related,browse" || c.UnknownBits != "2147483648" {
		t.Fatal(c)
	}
}
func TestNoSecretsInPresentationProjection(t *testing.T) {
	cfg := FromSyncConfig(coresync.Config{Remote: "https://user:SECRET@example.invalid/r.git?token=SECRET#SECRET", SSHKey: "SECRET", KnownHosts: "SECRET"})
	status := FromSyncStatus(coresync.Status{Remote: "https://user:SECRET@example.invalid/r.git", Auth: "SECRET", AuthHint: "SECRET", LastError: "SECRET", Warnings: []string{"SECRET"}, KeyIssue: "SECRET"})
	stream := FromStream(media.Stream{URL: "https://example.invalid?token=SECRET", Headers: map[string]string{"Authorization": "SECRET", "Cookie": "SECRET"}})
	for _, v := range []any{cfg, status, stream, FromPlaylist(store.Playlist{ScanError: "SECRET"})} {
		b, err := Marshal(v)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(b), "SECRET") {
			t.Fatalf("secret exposed: %T", v)
		}
	}
	if cfg.Remote != "https://example.invalid/r.git" || !status.HasError || status.WarningCount != 1 {
		t.Fatal("safe status lost")
	}
	for _, unsafe := range []string{"https://invalid%secret/r", "user:SECRET@host:repo", "host:repo?SECRET"} {
		if PublicRemote(unsafe) != "" {
			t.Fatalf("unsafe remote retained: %q", unsafe)
		}
	}
}
func TestEngineProjectionCopiesHeaders(t *testing.T) {
	h := map[string]string{"Referer": "https://example.invalid"}
	e := FromEngineStream(media.Stream{Headers: h})
	h["Cookie"] = "SECRET"
	if _, exists := e.Headers["Cookie"]; exists {
		t.Fatal("engine stream aliases mutable core headers")
	}
}
func TestMarshalRejectsLossyAndMalformedValues(t *testing.T) {
	bad := []any{Track{CID: "9223372036854775808"}, Track{CID: "01"}, QueueSnapshot{IDs: []string{}, PositionMS: math.MaxInt64}, PlaybackSnapshot{Queue: []Song{}, Volume: math.NaN()}, BrowseEntry{}, BrowseEntry{Ref: &BrowseRef{}, Track: &Track{}}, QueueSnapshot{IDs: nil}, Timestamp("2026-02-31T00:00:00.000Z")}
	for _, v := range bad {
		if _, err := Marshal(v); err == nil {
			t.Errorf("accepted invalid %T", v)
		}
	}
}

func TestValidatedInputConversions(t *testing.T) {
	ref := source.Ref{Source: source.NetEase, ExternalID: "program:2066770638", Page: 1, CID: math.MaxInt64}
	if got, err := FromRef(ref).Core(); err != nil || got != ref {
		t.Fatalf("ref roundtrip: %+v %v", got, err)
	}
	for _, v := range []TrackRef{{Source: "netease", ExternalID: "program:1", Page: 0, CID: "0"}, {Source: "netease", ExternalID: "program:1", Page: 1, CID: "01"}, {Source: "netease", ExternalID: "program:1", Page: 1, CID: "-1"}, {Source: "", ExternalID: "1", Page: 1, CID: "0"}} {
		if _, err := v.Core(); err == nil {
			t.Errorf("accepted invalid ref: %+v", v)
		}
	}
	if got, err := (BrowseRef{Source: "netease", Kind: "radios"}).Core(); err != nil || got.Kind != source.BrowseRadios {
		t.Fatal(got, err)
	}
	for _, v := range []BrowseRef{{Source: "netease", Kind: "radios", ID: "1"}, {Source: "netease", Kind: "artist"}, {Source: "netease", Kind: "future", ID: "1"}} {
		if _, err := v.Core(); err == nil {
			t.Errorf("accepted invalid browse ref: %+v", v)
		}
	}
	if got, err := Quality("lossless").Core(); err != nil || got != source.QualityLossless {
		t.Fatal(got, err)
	}
	if _, err := Quality("unknown:99").Core(); err == nil {
		t.Fatal("unknown quality accepted as command")
	}
	if got, err := PlaybackMode("ordered").Core(); err != nil || got != player.ModeOrdered {
		t.Fatal(got, err)
	}
	if _, err := PlaybackMode("future").Core(); err == nil {
		t.Fatal("unknown mode accepted as command")
	}
	if got, err := (Clip{StartMS: 1234}).Core(); err != nil || got.EndMS != 0 {
		t.Fatal(got, err)
	}
	for _, v := range []Clip{{StartMS: -1}, {StartMS: 10, EndMS: 9}, {StartMS: 10, EndMS: 10}, {EndMS: math.MaxInt64}} {
		if _, err := v.Core(); err == nil {
			t.Errorf("accepted invalid clip: %+v", v)
		}
	}
}
