package management

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/router-for-me/CLIProxyAPI/v7/internal/usagestats"
	coreauth "github.com/router-for-me/CLIProxyAPI/v7/sdk/cliproxy/auth"
)

// probeModel is the cheapest Claude model that OAuth tokens are reliably allowed
// to call; it is only used to elicit the anthropic-ratelimit-unified-* headers.
const probeModel = "claude-haiku-4-5-20251001"

// GetUsageStatus returns per-account usage and limiter status: the engine's own
// quota/status tracking plus the latest captured provider usage snapshot
// (Anthropic rolling 5h / weekly windows). Keyed so the app can merge it onto
// the account list by name. KorpProxy-specific.
func (h *Handler) GetUsageStatus(c *gin.Context) {
	if h == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "handler not initialized"})
		return
	}
	h.mu.Lock()
	manager := h.authManager
	h.mu.Unlock()
	if manager == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "core auth manager unavailable"})
		return
	}

	accounts := make([]gin.H, 0)
	for _, auth := range manager.List() {
		if auth == nil {
			continue
		}
		name := strings.TrimSpace(auth.FileName)
		if name == "" {
			name = strings.TrimSpace(auth.ID)
		}
		entry := gin.H{
			"id":          auth.ID,
			"name":        name,
			"provider":    strings.TrimSpace(auth.Provider),
			"status":      auth.Status,
			"disabled":    auth.Disabled,
			"unavailable": auth.Unavailable,
			"quota":       auth.Quota,
		}
		if u, ok := usagestats.Get(auth.ID); ok {
			entry["usage"] = u
		}
		accounts = append(accounts, entry)
	}

	c.JSON(http.StatusOK, gin.H{"accounts": accounts})
}

// ProbeUsage issues a minimal request per Claude OAuth account to refresh the
// captured usage snapshot (rolling 5h / weekly windows). It is best-effort:
// individual failures are reported but never abort the batch. KorpProxy-specific.
func (h *Handler) ProbeUsage(c *gin.Context) {
	if h == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "handler not initialized"})
		return
	}
	h.mu.Lock()
	manager := h.authManager
	h.mu.Unlock()
	if manager == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "core auth manager unavailable"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 25*time.Second)
	defer cancel()

	updated := make([]string, 0)
	errs := make(map[string]string)
	for _, auth := range manager.List() {
		if auth == nil {
			continue
		}
		provider := strings.ToLower(strings.TrimSpace(auth.Provider))
		if provider != "claude" && provider != "anthropic" {
			continue
		}
		name := strings.TrimSpace(auth.FileName)
		if name == "" {
			name = strings.TrimSpace(auth.ID)
		}
		token, baseURL := claudeTokenFromAuth(auth)
		if token == "" {
			errs[name] = "no access token available"
			continue
		}
		if err := probeAnthropicUsage(ctx, auth.ID, token, baseURL); err != nil {
			errs[name] = err.Error()
			continue
		}
		updated = append(updated, name)
	}

	c.JSON(http.StatusOK, gin.H{"updated": updated, "errors": errs})
}

// claudeTokenFromAuth extracts the bearer token and base URL for a Claude auth,
// mirroring the executor's credential resolution.
func claudeTokenFromAuth(a *coreauth.Auth) (token, baseURL string) {
	baseURL = "https://api.anthropic.com"
	if a == nil {
		return "", baseURL
	}
	if a.Attributes != nil {
		if v := strings.TrimSpace(a.Attributes["api_key"]); v != "" {
			token = v
		}
		if v := strings.TrimSpace(a.Attributes["base_url"]); v != "" {
			baseURL = v
		}
	}
	if token == "" && a.Metadata != nil {
		if v, ok := a.Metadata["access_token"].(string); ok {
			token = strings.TrimSpace(v)
		}
	}
	return token, baseURL
}

// probeAnthropicUsage sends one tiny request so Anthropic returns the unified
// rate-limit headers, then records them. The unified headers are present even on
// non-2xx responses, so usage is captured as long as the headers come back.
func probeAnthropicUsage(ctx context.Context, authID, token, baseURL string) error {
	body := []byte(fmt.Sprintf(`{"model":%q,"max_tokens":1,"messages":[{"role":"user","content":"hi"}]}`, probeModel))
	url := strings.TrimRight(baseURL, "/") + "/v1/messages"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("content-type", "application/json")
	req.Header.Set("authorization", "Bearer "+token)
	req.Header.Set("anthropic-version", "2023-06-01")
	req.Header.Set("anthropic-beta", "oauth-2025-04-20")

	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<16))

	usagestats.RecordFromHeaders(authID, resp.Header)
	if _, ok := usagestats.Get(authID); !ok {
		return fmt.Errorf("no usage headers returned (status %d)", resp.StatusCode)
	}
	return nil
}
