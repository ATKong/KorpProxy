package auth

import (
	"context"
	"testing"
	"time"

	"github.com/router-for-me/CLIProxyAPI/v7/internal/registry"
)

func newUsageExhaustionManager(authID, model string) *Manager {
	registry.GetGlobalRegistry().RegisterClient(authID, "claude", []*registry.ModelInfo{{ID: model, Type: "claude"}})
	m := &Manager{
		auths:     map[string]*Auth{authID: {ID: authID, Provider: "claude"}},
		executors: map[string]ProviderExecutor{"claude": schedulerTestExecutor{}},
		hook:      NoopHook{},
	}
	m.scheduler = newAuthScheduler(&RoundRobinSelector{})
	m.scheduler.upsertAuth(m.auths[authID].Clone())
	return m
}

func TestMarkUsageExhausted_BlocksModelUntilReset(t *testing.T) {
	const authID, model = "claude-exhaust-1", "claude-sonnet-4-6"
	m := newUsageExhaustionManager(authID, model)
	t.Cleanup(func() { registry.GetGlobalRegistry().RegisterClient(authID, "claude", nil) })

	reset := time.Now().Add(2 * time.Hour)
	m.MarkUsageExhausted(authID, reset)

	auth := m.auths[authID]
	state := auth.ModelStates[model]
	if state == nil {
		t.Fatalf("model state for %q not created", model)
	}
	if !state.Unavailable {
		t.Fatalf("state.Unavailable = false, want true")
	}
	if state.Quota.Reason != usageLimitReason {
		t.Fatalf("state.Quota.Reason = %q, want %q", state.Quota.Reason, usageLimitReason)
	}
	if !state.NextRetryAfter.Equal(reset) {
		t.Fatalf("state.NextRetryAfter = %v, want %v", state.NextRetryAfter, reset)
	}

	// The account must now be blocked for selection on this model.
	blocked, reason, next := isAuthBlockedForModel(auth, model, time.Now())
	if !blocked || reason != blockReasonCooldown {
		t.Fatalf("isAuthBlockedForModel = (%v, %v), want (true, cooldown)", blocked, reason)
	}
	if next.Before(time.Now()) {
		t.Fatalf("next retry %v is not in the future", next)
	}
}

func TestMarkUsageExhausted_RecoversAfterReset(t *testing.T) {
	const authID, model = "claude-exhaust-2", "claude-sonnet-4-6"
	m := newUsageExhaustionManager(authID, model)
	t.Cleanup(func() { registry.GetGlobalRegistry().RegisterClient(authID, "claude", nil) })

	reset := time.Now().Add(30 * time.Minute)
	m.MarkUsageExhausted(authID, reset)

	auth := m.auths[authID]
	// Before reset: blocked.
	if blocked, _, _ := isAuthBlockedForModel(auth, model, time.Now()); !blocked {
		t.Fatalf("account should be blocked before reset")
	}
	// After reset: automatically available again, no explicit clear needed.
	if blocked, _, _ := isAuthBlockedForModel(auth, model, reset.Add(time.Minute)); blocked {
		t.Fatalf("account should recover after reset")
	}
}

func TestMarkUsageExhausted_IgnoresPastReset(t *testing.T) {
	const authID, model = "claude-exhaust-3", "claude-sonnet-4-6"
	m := newUsageExhaustionManager(authID, model)
	t.Cleanup(func() { registry.GetGlobalRegistry().RegisterClient(authID, "claude", nil) })

	m.MarkUsageExhausted(authID, time.Now().Add(-time.Minute))

	if state := m.auths[authID].ModelStates[model]; state != nil && state.Unavailable {
		t.Fatalf("past reset should not block the account")
	}
}

func TestMarkResultSuccess_PreservesActiveUsageBlock(t *testing.T) {
	const authID, model = "claude-exhaust-5", "claude-sonnet-4-6"
	m := newUsageExhaustionManager(authID, model)
	t.Cleanup(func() { registry.GetGlobalRegistry().RegisterClient(authID, "claude", nil) })

	reset := time.Now().Add(time.Hour)
	m.MarkUsageExhausted(authID, reset)

	// A request that streams through successfully while the window is still maxed
	// must NOT clear the proactive block (headers are authoritative).
	m.MarkResult(context.Background(), Result{AuthID: authID, Model: model, Success: true})

	auth := m.auths[authID]
	if blocked, _, _ := isAuthBlockedForModel(auth, model, time.Now()); !blocked {
		t.Fatalf("active usage block must survive a successful request")
	}
	if state := auth.ModelStates[model]; state == nil || state.Quota.Reason != usageLimitReason {
		t.Fatalf("usage-limit quota reason must be preserved, got %+v", auth.ModelStates[model])
	}
}

func TestMarkResultSuccess_ClearsExpiredUsageBlock(t *testing.T) {
	const authID, model = "claude-exhaust-6", "claude-sonnet-4-6"
	m := newUsageExhaustionManager(authID, model)
	t.Cleanup(func() { registry.GetGlobalRegistry().RegisterClient(authID, "claude", nil) })

	// Simulate a block whose window already reset; a later success should clear it.
	state := ensureModelState(m.auths[authID], model)
	state.Unavailable = true
	state.Status = StatusError
	state.NextRetryAfter = time.Now().Add(-time.Minute)
	state.Quota = QuotaState{Exceeded: true, Reason: usageLimitReason, NextRecoverAt: state.NextRetryAfter}

	m.MarkResult(context.Background(), Result{AuthID: authID, Model: model, Success: true})

	if blocked, _, _ := isAuthBlockedForModel(m.auths[authID], model, time.Now()); blocked {
		t.Fatalf("expired usage block must clear on success")
	}
}

func TestMarkUsageExhausted_UnknownAuthIsNoop(t *testing.T) {
	const authID, model = "claude-exhaust-4", "claude-sonnet-4-6"
	m := newUsageExhaustionManager(authID, model)
	t.Cleanup(func() { registry.GetGlobalRegistry().RegisterClient(authID, "claude", nil) })

	// Must not panic and must not affect the known account.
	m.MarkUsageExhausted("does-not-exist", time.Now().Add(time.Hour))

	if state := m.auths[authID].ModelStates[model]; state != nil && state.Unavailable {
		t.Fatalf("unrelated account must not be blocked")
	}
}
