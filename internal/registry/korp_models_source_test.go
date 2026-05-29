package registry

import "testing"

func TestKorpApplyModelsSource(t *testing.T) {
	base := []string{"https://upstream/a.json", "https://upstream/b.json"}

	t.Run("empty env is a no-op", func(t *testing.T) {
		got, changed := korpApplyModelsSource("", base)
		if changed {
			t.Fatalf("expected no change, got changed=true (%v)", got)
		}
		if len(got) != len(base) {
			t.Fatalf("expected base unchanged, got %v", got)
		}
	})

	t.Run("prepends our url, keeps upstream as fallback", func(t *testing.T) {
		got, changed := korpApplyModelsSource("https://korp/models.json", base)
		if !changed {
			t.Fatal("expected changed=true")
		}
		if len(got) != 3 || got[0] != "https://korp/models.json" {
			t.Fatalf("expected korp url first with fallback, got %v", got)
		}
	})

	t.Run("supports multiple urls and de-dupes", func(t *testing.T) {
		got, _ := korpApplyModelsSource("https://korp/models.json, https://upstream/a.json", base)
		if len(got) != 3 {
			t.Fatalf("expected dedupe to 3 urls, got %v", got)
		}
		if got[0] != "https://korp/models.json" || got[1] != "https://upstream/a.json" {
			t.Fatalf("unexpected order: %v", got)
		}
	})
}
