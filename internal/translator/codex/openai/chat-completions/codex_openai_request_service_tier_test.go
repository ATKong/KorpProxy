package chat_completions

import (
	"testing"

	"github.com/tidwall/gjson"
)

func TestConvertOpenAIRequestToCodexServiceTier(t *testing.T) {
	cases := []struct {
		name  string
		input string
		want  string // "" means service_tier should be absent
	}{
		{name: "priority kept", input: `{"model":"gpt-5.5","service_tier":"priority","messages":[]}`, want: "priority"},
		{name: "flex dropped", input: `{"model":"gpt-5.5","service_tier":"flex","messages":[]}`, want: ""},
		{name: "absent stays absent", input: `{"model":"gpt-5.5","messages":[]}`, want: ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			out := ConvertOpenAIRequestToCodex("gpt-5.5", []byte(tc.input), true)
			got := gjson.GetBytes(out, "service_tier")
			if tc.want == "" {
				if got.Exists() {
					t.Fatalf("service_tier present, want absent; output=%s", out)
				}
				return
			}
			if got.String() != tc.want {
				t.Fatalf("service_tier = %q, want %q; output=%s", got.String(), tc.want, out)
			}
		})
	}
}

func TestConvertOpenAIRequestToCodexFastSuffix(t *testing.T) {
	input := []byte(`{"model":"gpt-5.5-fast","messages":[]}`)
	out := ConvertOpenAIRequestToCodex("gpt-5.5-fast", input, true)

	if got := gjson.GetBytes(out, "service_tier").String(); got != "priority" {
		t.Fatalf("service_tier = %q, want %q; output=%s", got, "priority", out)
	}
	if got := gjson.GetBytes(out, "model").String(); got != "gpt-5.5" {
		t.Fatalf("model = %q, want %q (suffix should be stripped); output=%s", got, "gpt-5.5", out)
	}
}
