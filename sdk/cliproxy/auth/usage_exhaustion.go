package auth

import (
	"context"
	"strings"
	"time"

	"github.com/router-for-me/CLIProxyAPI/v7/internal/registry"
	log "github.com/sirupsen/logrus"
)

// usageLimitReason marks per-model quota state that was set proactively from
// provider usage headers (rolling-window utilization) rather than from a live
// 429 response. Keeping it distinct from the reactive "quota" reason makes the
// two sources legible in logs and the dashboard.
//
// This is a KorpProxy-specific addition (not part of upstream CLIProxyAPI) that
// powers proactive multi-account rotation: an account is taken out of the
// rotation the moment the provider reports a fully consumed window, instead of
// only after it returns a 429.
const usageLimitReason = "usage_limit"

// MarkUsageExhausted proactively blocks an account until reset when the provider
// reports a fully consumed rolling usage window (e.g. Anthropic's unified 5h/7d
// rate-limit headers at 100% utilization). It marks every model the account
// serves as unavailable until reset, so the scheduler rotates to another
// account BEFORE this one would start returning 429s.
//
// Recovery is automatic: the existing cooldown machinery promotes the account
// back to ready once reset passes (no explicit clear is required, and a later
// successful request resets its state via MarkResult).
//
// It is a no-op when authID is unknown, reset is not in the future, or the
// account serves no registered models.
func (m *Manager) MarkUsageExhausted(authID string, reset time.Time) {
	if m == nil {
		return
	}
	authID = strings.TrimSpace(authID)
	if authID == "" {
		return
	}
	now := time.Now()
	if !reset.After(now) {
		// Without a future reset we cannot auto-recover, so blocking would risk
		// pinning the account off indefinitely. Leave it to reactive 429 handling.
		return
	}

	// Snapshot the account's models without holding the manager lock; the model
	// registry maintains its own synchronization.
	models := registry.GetGlobalRegistry().GetModelsForClient(authID)
	if len(models) == 0 {
		return
	}

	var snapshot *Auth
	m.mu.Lock()
	if auth, ok := m.auths[authID]; ok && auth != nil {
		changed := false
		for _, model := range models {
			if model == nil {
				continue
			}
			modelKey := canonicalModelKey(model.ID)
			if modelKey == "" {
				continue
			}
			state := ensureModelState(auth, modelKey)
			if usageBlockCurrent(state, reset) {
				continue
			}
			state.Unavailable = true
			state.Status = StatusError
			state.StatusMessage = "usage limit reached"
			state.NextRetryAfter = reset
			state.Quota = QuotaState{
				Exceeded:      true,
				Reason:        usageLimitReason,
				NextRecoverAt: reset,
			}
			state.UpdatedAt = now
			changed = true
		}
		if changed {
			updateAggregatedAvailability(auth, now)
			auth.UpdatedAt = now
			if errPersist := m.persist(context.Background(), auth); errPersist != nil {
				log.Warnf("usage-rotation: persist account %s failed: %v", authID, errPersist)
			}
			snapshot = auth.Clone()
		}
	}
	m.mu.Unlock()

	if snapshot == nil {
		return
	}
	if m.scheduler != nil {
		m.scheduler.upsertAuth(snapshot)
	}
	m.invalidateSessionAffinity(authID)
	log.Infof("usage-rotation: account %s fully maxed; routing elsewhere until %s", authID, reset.Format(time.RFC3339))
}

// usageBlockCurrent reports whether state already carries a proactive usage
// block that lasts at least until reset, so repeated exhausted responses do not
// churn scheduler state.
func usageBlockCurrent(state *ModelState, reset time.Time) bool {
	if state == nil || !state.Unavailable {
		return false
	}
	if state.Quota.Reason != usageLimitReason {
		return false
	}
	return !state.NextRetryAfter.Before(reset)
}

// hasActiveUsageLimitBlock reports whether state carries a proactive usage block
// whose window has not yet reset. The success path consults this so a request
// that streams through while the provider reports a fully consumed window does
// not clear the block: the rolling-window headers are authoritative, and one
// request squeezing past does not restore headroom. The block self-heals once
// NextRetryAfter passes.
func hasActiveUsageLimitBlock(state *ModelState, now time.Time) bool {
	if state == nil || !state.Unavailable {
		return false
	}
	if state.Quota.Reason != usageLimitReason {
		return false
	}
	return state.NextRetryAfter.After(now)
}
