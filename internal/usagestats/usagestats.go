// Package usagestats stores the latest provider rate-limit/usage snapshot per
// account, captured from upstream response headers. This is a KorpProxy-specific
// addition (not part of upstream CLIProxyAPI) used to surface per-account usage
// (e.g. Anthropic's rolling 5-hour and weekly windows) in the menu-bar app.
package usagestats

import (
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Window holds utilization for a single rolling rate-limit window.
type Window struct {
	// Utilization is a fraction in [0,1]; it may exceed 1 when in overage.
	Utilization float64 `json:"utilization"`
	// Reset is the unix epoch (seconds) when the window fully replenishes.
	Reset int64 `json:"reset,omitempty"`
	// Status mirrors the provider status (e.g. active / warning / rate_limited).
	Status string `json:"status,omitempty"`
}

// Usage is the latest unified usage snapshot for an account.
type Usage struct {
	FiveHour            *Window `json:"five_hour,omitempty"`
	SevenDay            *Window `json:"seven_day,omitempty"`
	OverallStatus       string  `json:"overall_status,omitempty"`
	RepresentativeClaim string  `json:"representative_claim,omitempty"`
	// UpdatedAt is the unix epoch (seconds) when this snapshot was captured.
	UpdatedAt int64 `json:"updated_at"`
}

var (
	mu    sync.RWMutex
	store = make(map[string]Usage)

	// exhaustionHook, when set, is invoked after each snapshot whose account is
	// fully maxed on a rolling window. It lets a higher layer (the auth manager)
	// proactively rotate away from the account without usagestats importing it,
	// which would create an import cycle. resetUnix is the epoch (seconds) at
	// which the blocking window recovers.
	exhaustionHook   func(authID string, resetUnix int64)
	exhaustionHookMu sync.RWMutex
)

// SetExhaustionHook registers the callback invoked when an account becomes fully
// maxed. Passing nil clears it. Safe for concurrent use.
func SetExhaustionHook(hook func(authID string, resetUnix int64)) {
	exhaustionHookMu.Lock()
	exhaustionHook = hook
	exhaustionHookMu.Unlock()
}

func notifyExhaustion(authID string, snapshot Usage) {
	exhaustionHookMu.RLock()
	hook := exhaustionHook
	exhaustionHookMu.RUnlock()
	if hook == nil {
		return
	}
	if resetUnix, ok := snapshot.ExhaustedUntil(); ok {
		hook(authID, resetUnix)
	}
}

// RecordFromHeaders parses a provider's rate-limit response headers and stores a
// snapshot for authID. It understands Anthropic's anthropic-ratelimit-unified-*
// headers (Claude) and OpenAI's x-codex-* headers (Codex/ChatGPT). It is a no-op
// when authID is empty or when no recognized headers are present, so responses
// from other providers never clobber state.
func RecordFromHeaders(authID string, h http.Header) {
	if strings.TrimSpace(authID) == "" || h == nil {
		return
	}
	snapshot := parseAnthropic(h)
	if snapshot == nil {
		snapshot = parseCodex(h)
	}
	if snapshot == nil {
		return
	}
	snapshot.UpdatedAt = time.Now().Unix()
	mu.Lock()
	store[authID] = *snapshot
	mu.Unlock()

	notifyExhaustion(authID, *snapshot)
}

// parseAnthropic reads anthropic-ratelimit-unified-* headers (Claude). Returns
// nil when none are present.
func parseAnthropic(h http.Header) *Usage {
	five := parseWindow(h, "5h", "five_hour")
	seven := parseWindow(h, "7d", "seven_day")
	overall := firstHeader(h, "anthropic-ratelimit-unified-status")
	claim := firstHeader(h, "anthropic-ratelimit-unified-representative-claim")
	if five == nil && seven == nil && overall == "" && claim == "" {
		return nil
	}
	return &Usage{
		FiveHour:            five,
		SevenDay:            seven,
		OverallStatus:       overall,
		RepresentativeClaim: claim,
	}
}

// parseCodex reads OpenAI's x-codex-* rate-limit headers (Codex/ChatGPT). The
// primary window is the rolling session limit (typically 5h) and the secondary
// is the longer window (typically weekly), mirroring Claude's 5h/7d shape.
// used-percent is 0–100 (converted to a 0–1 fraction); reset is taken from the
// absolute -reset-at epoch when present, else now + -reset-after-seconds.
func parseCodex(h http.Header) *Usage {
	primary := parseCodexWindow(h, "primary")
	secondary := parseCodexWindow(h, "secondary")
	if primary == nil && secondary == nil {
		return nil
	}
	return &Usage{
		FiveHour:      primary,
		SevenDay:      secondary,
		OverallStatus: firstHeader(h, "x-codex-plan-type"),
	}
}

func parseCodexWindow(h http.Header, which string) *Window {
	used := firstHeader(h, "x-codex-"+which+"-used-percent")
	windowMin := firstHeader(h, "x-codex-"+which+"-window-minutes")
	resetAt := firstHeader(h, "x-codex-"+which+"-reset-at")
	resetAfter := firstHeader(h, "x-codex-"+which+"-reset-after-seconds")
	if used == "" && windowMin == "" && resetAt == "" && resetAfter == "" {
		return nil
	}
	w := &Window{}
	if used != "" {
		if f, err := strconv.ParseFloat(used, 64); err == nil {
			w.Utilization = f / 100.0
		}
	}
	if resetAt != "" {
		if n, err := strconv.ParseInt(resetAt, 10, 64); err == nil {
			w.Reset = n
		}
	}
	if w.Reset == 0 && resetAfter != "" {
		if n, err := strconv.ParseInt(resetAfter, 10, 64); err == nil && n > 0 {
			w.Reset = time.Now().Unix() + n
		}
	}
	return w
}

// Get returns the latest snapshot for authID.
func Get(authID string) (Usage, bool) {
	mu.RLock()
	snapshot, ok := store[authID]
	mu.RUnlock()
	return snapshot, ok
}

// ExhaustedUntil reports whether the account is fully maxed out on any of its
// rolling windows, returning the unix epoch (seconds) at which the blocking
// window resets. ok is false when the account still has headroom.
//
// "Fully maxed" means a window's status is "rejected"/"exceeded" or its
// utilization has reached 1.0 (100%). When several windows are exhausted, the
// latest reset wins so the account is skipped until every blocked window has
// recovered. This drives proactive rotation: an account is taken out of the
// rotation BEFORE it returns a 429, using the rate-limit headers the provider
// already reports on every response.
func (u Usage) ExhaustedUntil() (resetUnix int64, ok bool) {
	for _, w := range []*Window{u.FiveHour, u.SevenDay} {
		if !windowExhausted(w) {
			continue
		}
		ok = true
		if w.Reset > resetUnix {
			resetUnix = w.Reset
		}
	}
	return resetUnix, ok
}

// windowExhausted reports whether a single window is fully consumed.
func windowExhausted(w *Window) bool {
	if w == nil {
		return false
	}
	switch strings.ToLower(strings.TrimSpace(w.Status)) {
	case "rejected", "exceeded", "blocked":
		return true
	}
	// Utilization is a fraction in [0,1] (may exceed 1 in overage); treat >= 1
	// as fully maxed.
	return w.Utilization >= 1.0
}

// parseWindow reads the utilization/reset/status headers for a window, trying
// each provided key spelling (e.g. "5h" and "five_hour").
func parseWindow(h http.Header, keys ...string) *Window {
	var util, reset, status string
	for _, k := range keys {
		if util == "" {
			util = firstHeader(h, "anthropic-ratelimit-unified-"+k+"-utilization")
		}
		if reset == "" {
			reset = firstHeader(h, "anthropic-ratelimit-unified-"+k+"-reset")
		}
		if status == "" {
			status = firstHeader(h, "anthropic-ratelimit-unified-"+k+"-status")
		}
	}
	if util == "" && reset == "" && status == "" {
		return nil
	}
	w := &Window{Status: status}
	if util != "" {
		if f, err := strconv.ParseFloat(util, 64); err == nil {
			w.Utilization = f
		}
	}
	if reset != "" {
		if n, err := strconv.ParseInt(reset, 10, 64); err == nil {
			w.Reset = n
		}
	}
	return w
}

func firstHeader(h http.Header, key string) string {
	return strings.TrimSpace(h.Get(key))
}
