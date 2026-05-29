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
)

// RecordFromHeaders parses anthropic-ratelimit-unified-* response headers and
// stores a snapshot for authID. It is a no-op when authID is empty or when no
// unified headers are present (so non-Claude responses never clobber state).
func RecordFromHeaders(authID string, h http.Header) {
	if strings.TrimSpace(authID) == "" || h == nil {
		return
	}
	five := parseWindow(h, "5h", "five_hour")
	seven := parseWindow(h, "7d", "seven_day")
	overall := firstHeader(h, "anthropic-ratelimit-unified-status")
	claim := firstHeader(h, "anthropic-ratelimit-unified-representative-claim")
	if five == nil && seven == nil && overall == "" && claim == "" {
		return
	}
	snapshot := Usage{
		FiveHour:            five,
		SevenDay:            seven,
		OverallStatus:       overall,
		RepresentativeClaim: claim,
		UpdatedAt:           time.Now().Unix(),
	}
	mu.Lock()
	store[authID] = snapshot
	mu.Unlock()
}

// Get returns the latest snapshot for authID.
func Get(authID string) (Usage, bool) {
	mu.RLock()
	snapshot, ok := store[authID]
	mu.RUnlock()
	return snapshot, ok
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
