# Mini Match design QA

## Evidence

- Source visual truth:
  - `/Users/yazdan/.codex/worktrees/c306/mini-match/docs/designs/home-create-join.png`
  - `/Users/yazdan/.codex/worktrees/c306/mini-match/docs/designs/lobby-lock-number.png`
  - `/Users/yazdan/.codex/worktrees/c306/mini-match/docs/designs/result-lowest-unique.png`
- Implementation captures:
  - Home: `/var/folders/mq/r3cnb2x16vz4lsrqyx90y27h0000gn/T/screenshot_optimized_5ae04814-7874-453f-88be-ee8582fcd854.jpg`
  - Locked lobby: `/var/folders/mq/r3cnb2x16vz4lsrqyx90y27h0000gn/T/screenshot_optimized_99ae046a-3a5f-4409-8aee-730fb48bec11.jpg`
  - Result: `/var/folders/mq/r3cnb2x16vz4lsrqyx90y27h0000gn/T/screenshot_optimized_69f5da79-85ee-4fbc-8abe-b4c6288babde.jpg`
- Combined comparison evidence:
  - `/tmp/mini-match-home-comparison-final.png`
  - `/tmp/mini-match-lobby-comparison-final.png`
  - `/tmp/mini-match-result-comparison-final.png`
- Viewport: iPhone 17 simulator, portrait; optimized captures are 368 × 800 pixels. CSS size and browser density do not apply to this native SwiftUI app.
- Source dimensions: 853 × 1844 pixels. Each source was proportionally scaled to 368 × 796 and padded to 368 × 800 before being placed beside its implementation capture; no source image was edited.
- States compared: home; host lobby after all three preview players locked; revealed result where Maya and Zoe chose 2 and Liam won with 5.

## Findings

No actionable P0, P1, or P2 differences remain.

- Typography: native rounded system display text preserves the bold, friendly hierarchy and remains readable at the device viewport.
- Spacing and layout: the three screens retain the reference hierarchy and primary actions. The result density was reduced so every selection and the next-round action remain visible without scrolling.
- Colors: ivory, navy, royal blue, and coral consistently map to the reference palette with accessible status-bar contrast.
- Image quality: the sketches' generated tabletop decoration and sample portraits are not standalone production assets, so the functional slice uses native SF Symbols and initials. This is a P3 fidelity gap, not a usability blocker.
- Copy: create/join, private lock, host reveal, duplicate exclusion, lowest-unique winner, and first-to-five scoring match the approved flow.

Focused crops were not needed: the normalized 736 × 800 side-by-side comparisons keep the logo, controls, score, and result rows readable at full size.

## Comparison history

1. Initial captures exposed three P2 issues: white status content lacked contrast on ivory; the create form was translucent and validation dismissed it; and the result's primary action fell below the viewport.
2. The app now provides a navy status-safe region, an opaque form with inline validation, and a compact result layout. The final comparison files above show the post-fix home, lobby, and complete result states.

## Follow-up polish

- P3: add approved standalone decorative art or real profile photos when those assets and profile data exist.

final result: passed
