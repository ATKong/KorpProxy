import AppKit
import SwiftUI

/// Brand identity for a provider: the asset-catalog logo (if any), an SF Symbol
/// fallback, and the brand accent color. Resolved by matching the provider
/// string the engine returns (e.g. "anthropic", "codex"), the provider keys the
/// add-account flow uses (e.g. "xai", "claude-api-key"), or the friendly group
/// labels shown in the Models tab (e.g. "OpenAI / Codex").
struct ProviderBrand {
    let assetName: String?
    let symbol: String
    let tint: Color

    /// Match on substrings so raw keys, API-key segments, and friendly labels
    /// all resolve to the same brand.
    static func forProvider(_ provider: String?) -> ProviderBrand {
        let p = (provider ?? "").lowercased()
        if p.contains("gemini") || p.contains("google") || p.contains("vertex") || p.contains("aistudio") {
            return .init(assetName: "ProviderGemini", symbol: "sparkle",
                         tint: Color(red: 0.19, green: 0.52, blue: 1.0))      // #3186FF
        }
        if p.contains("antigravity") {
            return .init(assetName: "ProviderAntigravity", symbol: "arrow.up.circle",
                         tint: Color(red: 0.26, green: 0.52, blue: 0.96))     // #4285F4
        }
        if p.contains("claude") || p.contains("anthropic") {
            return .init(assetName: "ProviderClaude", symbol: "a.circle",
                         tint: Color(red: 0.85, green: 0.47, blue: 0.34))     // #D97757
        }
        if p.contains("codex") || p.contains("openai") || p.contains("gpt") {
            return .init(assetName: "ProviderOpenAI", symbol: "o.circle",
                         tint: Color(red: 0.06, green: 0.64, blue: 0.50))     // #10A37F
        }
        if p.contains("kimi") || p.contains("moonshot") {
            return .init(assetName: "ProviderKimi", symbol: "k.circle",
                         tint: Color(red: 0.01, green: 0.48, blue: 1.0))      // #027AFF
        }
        if p.contains("xai") || p.contains("x-ai") || p.contains("grok") {
            return .init(assetName: "ProviderGrok", symbol: "x.circle", tint: .primary)
        }
        return .init(assetName: nil, symbol: "person.crop.circle", tint: .secondary)
    }
}

/// Renders a provider's brand logo, scaled to fit a square of `size`. Falls back
/// to a tinted SF Symbol when the logo asset isn't available. Uses SwiftUI's
/// asset lookup so light/dark logo variants (OpenAI, Grok) switch automatically.
struct ProviderIcon: View {
    let provider: String?
    var size: CGFloat = 18

    private var brand: ProviderBrand { .forProvider(provider) }

    var body: some View {
        Group {
            if let asset = brand.assetName, NSImage(named: asset) != nil {
                Image(asset).resizable().scaledToFit()
            } else {
                Image(systemName: brand.symbol)
                    .font(.system(size: size * 0.66, weight: .semibold))
                    .foregroundStyle(brand.tint)
            }
        }
        .frame(width: size, height: size)
    }
}
