package helps

import (
	"net/http"
	"strconv"
	"strings"
	"time"
)

// ClaudeRetryAfter extracts how long to wait before retrying a rate-limited
// Anthropic response, so cooldowns track the provider's real reset instead of a
// synthetic exponential backoff.
//
// Resolution order (first hit wins):
//  1. Retry-After header (delta seconds or HTTP-date)
//  2. Retry-After-Ms header (milliseconds)
//  3. anthropic-ratelimit-unified-*-reset headers (unix epoch seconds) — the
//     soonest future window reset, i.e. when capacity next frees up.
//
// It only applies to rate-limit statuses (429, and 529 "overloaded"); other
// statuses return nil so non-quota errors keep their normal handling. A
// non-positive or absent hint also returns nil.
func ClaudeRetryAfter(status int, h http.Header, now time.Time) *time.Duration {
	if status != http.StatusTooManyRequests && status != 529 {
		return nil
	}
	if h == nil {
		return nil
	}

	if raw := strings.TrimSpace(h.Get("Retry-After")); raw != "" {
		if secs, err := strconv.ParseFloat(raw, 64); err == nil && secs > 0 {
			return durationPtr(time.Duration(secs * float64(time.Second)))
		}
		if when, err := http.ParseTime(raw); err == nil {
			if d := when.Sub(now); d > 0 {
				return durationPtr(d)
			}
		}
	}

	if raw := strings.TrimSpace(h.Get("Retry-After-Ms")); raw != "" {
		if ms, err := strconv.ParseFloat(raw, 64); err == nil && ms > 0 {
			return durationPtr(time.Duration(ms * float64(time.Millisecond)))
		}
	}

	// Fall back to the unified rate-limit reset headers. Pick the soonest future
	// reset across the rolling windows; that is the earliest moment a retry could
	// succeed.
	var soonest time.Time
	for _, key := range []string{
		"anthropic-ratelimit-unified-reset",
		"anthropic-ratelimit-unified-5h-reset",
		"anthropic-ratelimit-unified-7d-reset",
		"anthropic-ratelimit-unified-five_hour-reset",
		"anthropic-ratelimit-unified-seven_day-reset",
	} {
		raw := strings.TrimSpace(h.Get(key))
		if raw == "" {
			continue
		}
		epoch, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || epoch <= 0 {
			continue
		}
		reset := time.Unix(epoch, 0)
		if !reset.After(now) {
			continue
		}
		if soonest.IsZero() || reset.Before(soonest) {
			soonest = reset
		}
	}
	if !soonest.IsZero() {
		return durationPtr(soonest.Sub(now))
	}

	return nil
}

func durationPtr(d time.Duration) *time.Duration {
	if d <= 0 {
		return nil
	}
	return &d
}
