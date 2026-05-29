// This file is a KorpProxy customization and is NOT part of upstream
// CLIProxyAPI. It lets KorpProxy point the model-catalog updater at our own
// source without editing upstream files (editing models.json or model_updater.go
// directly would conflict on nearly every upstream sync).
//
// Set KORP_MODELS_URL to one or more comma-separated https URLs pointing at a
// models.json. They are tried first, with upstream's URLs kept as fallback, so
// a new model added to our catalog is picked up by every running instance on
// the next refresh (startup + every 3h) with no rebuild.
package registry

import (
	"os"
	"strings"

	log "github.com/sirupsen/logrus"
)

// KorpModelsURLEnv is the environment variable KorpProxy reads to override the
// model-catalog source.
const KorpModelsURLEnv = "KORP_MODELS_URL"

func init() {
	if merged, changed := korpApplyModelsSource(os.Getenv(KorpModelsURLEnv), modelsURLs); changed {
		modelsURLs = merged
		log.Infof("registry: %s set; model catalog source order: %v", KorpModelsURLEnv, modelsURLs)
	}
}

// korpApplyModelsSource prepends the comma-separated URLs from env onto base,
// de-duplicating while preserving order. It returns the merged list and whether
// anything changed (so callers can avoid log noise when the env is unset).
func korpApplyModelsSource(env string, base []string) ([]string, bool) {
	var prepend []string
	for _, part := range strings.Split(env, ",") {
		if v := strings.TrimSpace(part); v != "" {
			prepend = append(prepend, v)
		}
	}
	if len(prepend) == 0 {
		return base, false
	}

	seen := make(map[string]struct{}, len(prepend)+len(base))
	merged := make([]string, 0, len(prepend)+len(base))
	for _, u := range append(prepend, base...) {
		if _, ok := seen[u]; ok {
			continue
		}
		seen[u] = struct{}{}
		merged = append(merged, u)
	}
	return merged, true
}
