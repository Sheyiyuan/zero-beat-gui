package wire

import (
	"github.com/sheyiyuan/zero-beat-core/downloader"
	"github.com/sheyiyuan/zero-beat-core/session"
	"github.com/sheyiyuan/zero-beat-core/source"
	coresync "github.com/sheyiyuan/zero-beat-core/sync"
	"strconv"
)

type LoginQR struct {
	Key string `json:"key"`
	URL string `json:"url"`
}
type LoginPoll struct {
	Code     int    `json:"code"`
	Message  string `json:"message"`
	LoggedIn bool   `json:"logged_in"`
	Expired  bool   `json:"expired"`
}
type BatchFailure struct {
	SongID string `json:"song_id"`
	Error  string `json:"error"`
}
type BatchResult struct {
	Succeeded []string       `json:"succeeded"`
	Skipped   []string       `json:"skipped"`
	Failed    []BatchFailure `json:"failed"`
}
type GUISettings struct {
	Theme       string            `json:"theme"`
	Palette     string            `json:"palette"`
	Accent      string            `json:"accent"`
	CloseAction string            `json:"close_action"`
	Shortcuts   map[string]string `json:"shortcuts"`
	Window      string            `json:"window"`
}

func FromLoginQR(v source.QRCode) LoginQR { return LoginQR{v.Key, v.URL} }
func FromLoginPoll(v source.LoginStatus) LoginPoll {
	return LoginPoll{v.Code, v.Message, v.LoggedIn, v.Expired}
}
func FromBatch(v session.BatchResult) BatchResult {
	return BatchResult{append([]string{}, v.Succeeded...), append([]string{}, v.Skipped...), items(v.Failed, func(v session.BatchItem) BatchFailure {
		return BatchFailure{v.SongID, batchError(v.Error)}
	})}
}
func FromGUISettings(v session.GUISettings) GUISettings {
	if v.Shortcuts == nil {
		v.Shortcuts = map[string]string{}
	}
	return GUISettings{v.Theme, v.Palette, v.Accent, v.CloseAction, v.Shortcuts, v.Window}
}
func (v GUISettings) Core() session.GUISettings {
	return session.GUISettings{Theme: v.Theme, Palette: v.Palette, Accent: v.Accent, CloseAction: v.CloseAction, Shortcuts: v.Shortcuts, Window: v.Window}
}

type DownloadTask struct {
	ID     int     `json:"id"`
	Song   Song    `json:"song"`
	State  string  `json:"state"`
	Done   Decimal `json:"done"`
	Total  Decimal `json:"total"`
	Path   string  `json:"path"`
	Failed bool    `json:"failed"`
}

func FromDownloadTask(v downloader.Task) DownloadTask {
	state := "queued"
	switch v.State {
	case downloader.Running:
		state = "running"
	case downloader.Failed:
		state = "failed"
	case downloader.Complete:
		state = "completed"
	}
	return DownloadTask{v.ID, FromSong(v.Song), state, Decimal(strconv.FormatInt(v.Done, 10)), Decimal(strconv.FormatInt(v.Total, 10)), v.Path, v.Err != nil}
}

type Work struct {
	ID      string `json:"id"`
	Action  string `json:"action"`
	State   string `json:"state"`
	Message string `json:"message"`
}

func FromWork(v session.Work) Work { return Work{v.ID, v.Action, v.State, v.Message} }

type SyncConflict struct {
	Index   int    `json:"index"`
	Entity  string `json:"entity"`
	Title   string `json:"title"`
	Summary string `json:"summary"`
	Both    bool   `json:"both"`
}

func FromSyncConflict(v coresync.ConflictEntity) SyncConflict {
	return SyncConflict{v.Index, v.Entity, coresync.DescribeEntity(v), coresync.SummarizeConflict(v), v.SupportsBoth()}
}

type SyncConflictList struct {
	TxID     string         `json:"tx_id"`
	Entities []SyncConflict `json:"entities"`
}

func FromSyncConflicts(v coresync.ConflictIndex) SyncConflictList {
	return SyncConflictList{v.TxID, items(v.Entities, FromSyncConflict)}
}

type Archive struct {
	Name  string `json:"name"`
	Title string `json:"title"`
}

func FromArchive(v session.Archive) Archive { return Archive{v.Name, v.Title} }

func batchError(message string) string {
	switch message {
	case "只能添加同来源曲目", "节目不能加入云端歌曲歌单", "未完成":
		return message
	}
	return "操作失败，请检查来源、账号或歌单权限后重试"
}
