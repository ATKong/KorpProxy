package management

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/router-for-me/CLIProxyAPI/v7/internal/usagestats"
)

// GetUsageStatus returns per-account usage and limiter status: the engine's own
// quota/status tracking plus the latest captured provider usage snapshot
// (Anthropic rolling 5h / weekly windows), populated passively from live traffic.
// Keyed by name so the app can merge it onto the account list. KorpProxy-specific.
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
