package rpc

import (
	"bytes"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"regexp"
	"strconv"
	"strings"
)

const maxSafeInteger int64 = 9007199254740991

var urlPattern = regexp.MustCompile(`(?i)https?://\S+`)

func redact(s string) string {
	return urlPattern.ReplaceAllString(s, "[url]")
}

type errorBody struct {
	Code    int            `json:"code"`
	Message string         `json:"message"`
	Data    map[string]any `json:"data"`
}

func (e *errorBody) Error() string {
	if e == nil {
		return ""
	}
	return e.Message
}

func errBody(code int, message string, data map[string]any) *errorBody {
	if data == nil {
		data = map[string]any{}
	}
	return &errorBody{Code: code, Message: message, Data: data}
}

type inbound struct {
	JSONRPC string
	ID      int64
	HasID   bool
	Method  string
	Params  json.RawMessage
	Result  json.RawMessage
	Error   *errorBody
}

func parseInbound(frame []byte) (inbound, error) {
	var head struct {
		JSONRPC string          `json:"jsonrpc"`
		ID      json.RawMessage `json:"id"`
		Method  string          `json:"method"`
		Params  json.RawMessage `json:"params"`
		Result  json.RawMessage `json:"result"`
		Error   json.RawMessage `json:"error"`
	}
	if err := json.Unmarshal(frame, &head); err != nil {
		return inbound{}, err
	}
	msg := inbound{
		JSONRPC: head.JSONRPC,
		Method:  head.Method,
		Params:  head.Params,
		Result:  head.Result,
	}
	if len(head.ID) > 0 && string(head.ID) != "null" {
		id, err := parseID(head.ID)
		if err != nil {
			return inbound{}, errBadID
		}
		msg.ID = id
		msg.HasID = true
	}
	if len(head.Error) > 0 && string(head.Error) != "null" {
		var body errorBody
		if err := json.Unmarshal(head.Error, &body); err != nil {
			return inbound{}, err
		}
		if body.Data == nil {
			body.Data = map[string]any{}
		}
		msg.Error = &body
	}
	return msg, nil
}

var errBadID = errors.New("rpc: bad id")

func parseID(raw json.RawMessage) (int64, error) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var num json.Number
	if err := dec.Decode(&num); err != nil {
		return 0, err
	}
	text := num.String()
	if strings.ContainsAny(text, ".eE") {
		return 0, errBadID
	}
	v, err := strconv.ParseInt(text, 10, 64)
	if err != nil || v < 1 || v > maxSafeInteger {
		return 0, errBadID
	}
	return v, nil
}

func appendNewline(body []byte) []byte {
	if len(body) == 0 || body[len(body)-1] != '\n' {
		return append(body, '\n')
	}
	return body
}

func encodeResult(id int64, result any, rpcErr *errorBody) ([]byte, error) {
	env := struct {
		JSONRPC string     `json:"jsonrpc"`
		ID      int64      `json:"id"`
		Result  any        `json:"result,omitempty"`
		Error   *errorBody `json:"error,omitempty"`
	}{JSONRPC: Version, ID: id}
	if rpcErr != nil {
		if rpcErr.Data == nil {
			rpcErr.Data = map[string]any{}
		}
		env.Error = rpcErr
	} else {
		if result == nil {
			result = map[string]any{}
		}
		env.Result = result
	}
	body, err := json.Marshal(env)
	if err != nil {
		return nil, err
	}
	return appendNewline(body), nil
}

func encodeRequest(id int64, method string, params any) ([]byte, error) {
	if params == nil {
		params = map[string]any{}
	}
	body, err := json.Marshal(struct {
		JSONRPC string `json:"jsonrpc"`
		ID      int64  `json:"id"`
		Method  string `json:"method"`
		Params  any    `json:"params"`
	}{Version, id, method, params})
	if err != nil {
		return nil, err
	}
	return appendNewline(body), nil
}

func encodeNotice(method string, params any) ([]byte, error) {
	if params == nil {
		params = map[string]any{}
	}
	body, err := json.Marshal(struct {
		JSONRPC string `json:"jsonrpc"`
		Method  string `json:"method"`
		Params  any    `json:"params"`
	}{Version, method, params})
	if err != nil {
		return nil, err
	}
	return appendNewline(body), nil
}

func tokenEqual(got, want string) bool {
	gb := []byte(got)
	wb := []byte(want)
	if len(gb) != len(wb) {
		subtle.ConstantTimeCompare(wb, wb)
		return false
	}
	return subtle.ConstantTimeCompare(gb, wb) == 1
}

func staleReason(data map[string]any) bool {
	if data == nil {
		return false
	}
	reason, _ := data["reason"].(string)
	return reason == "stale_playback"
}
