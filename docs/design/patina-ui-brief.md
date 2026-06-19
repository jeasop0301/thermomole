# Patina — UI Design Brief (for Claude Design)

Goal: a unique, beautiful, calm UI for a battery-longevity insight app. NOT a cockpit/dashboard. Few elements, clear hierarchy, everything essential visible. Native macOS menu-bar app feel.

## Concept
"Patina" = the beautiful finish a fine object earns as it ages. The app shows how your Mac's battery is aging — honestly — and what's speeding it up. Tone: calm, premium, organic, honest. Reassuring, not alarmist. Like a museum placard for a well-aged artifact, not an instrument panel.

## Theme / aesthetic
- **Mood**: quiet, sophisticated, warm-minimal. Lots of breathing room. One thing matters at a time.
- **Palette**: deep warm "ink" charcoal base (near-black with a faint green-brown undertone — not pure black). One calm primary = aged-copper **verdigris teal-green** (healthy / ideal aging). One *expressive* accent that **warms as aging accelerates**: sage-green (≈1×, ideal) → honey/amber (moderate) → terracotta/rust (high) — like copper warming to bronze. Soft parchment/off-white text. Restrained: one calm base + one shifting warmth accent. No neon, no pure red alarms.
- **Typography**: a refined display face for the wordmark and the big hero number (editorial — characterful serif or distinctive grotesk). Clean humanist sans for body. The hero numeral is large and confident.
- **Signature element**: ONE hero visual, not a wall of gauges. e.g. a soft organic "aging arc/ring" whose color = the current warmth accent and whose fill hints at the multiplier — or a single large numeral on a subtle patina-texture swatch. Calm, optional motion.
- **Shape/space**: large corner radii, generous whitespace, soft hairline separators (no hard grid). Flat surfaces, no glassmorphism/shadows/gradients.
- **Avoid**: cockpit density, multiple gauges, dense stat grids, hard dashboard cards, alarmist red, generic SaaS look.

## Content — primary screen (calm, in this order)
1. **Wordmark** "Patina" + tagline "See your battery age, honestly."
2. **Hero — Aging speed now**: big "≈ 1.7×"; caption "aging vs an ideal idle (25° / 50%)"; cause line ("Heat is the main driver right now" / "High charge + heat" / "Looking ideal"); honest micro-label "Relative estimate from published kinetics — not a capacity measurement." Color = warmth accent, shifts with the number.
3. **Why (2–3 live drivers)**: the inputs behind the number, tiny and calm — cell temperature (e.g. 36°), charge level (e.g. 64%), charging on/off. So the user sees *what's pushing it*. Not a big stat grid.
4. **This week — strain**: one line "This week ran 1.4× ideal · +2.6 aging-days" + a small 7-day trend (sparkline/dots, warmth-coded). Honest micro-label "relative estimate — not a capacity measurement."
5. **Outlook**: one line "At this trend, ~80% health in 8–14 months."
6. **Gentle action (only when relevant)**: one soft suggestion, e.g. "Unplug near 80% to ease aging" or "Let it cool." Never nagging.

## Content — secondary (tucked behind a "Details / Patterns" expander, NOT on the calm main view)
- When it runs hot — hour-of-day heat heatmap
- Heat vs health — observed correlation
- Health outlook — full projection band chart
- Longevity factors (battery / heat / charging / storage / memory) + the 0–100 longevity score — keep available but secondary; the aging speed is the headline now.

## Honesty guardrails (must hold in any generated UI)
- The multiplier is a **relative calendar-aging RATE** vs ideal, under published kinetics — always carry "not a capacity measurement."
- NEVER: "losing capacity N× faster", "N× more total/lifetime loss", any "−X% capacity" derived from the rate, or any "cold is good" message.
- Warmth accent encodes aging speed; reserve the strongest (rust) for genuinely high (≳3×), not for normal warmth.

## Paste-ready prompt for Claude Design
> Design a calm, premium macOS app screen for "Patina" — a battery-longevity insight app whose theme is graceful aging (verdigris/aged-copper). Dark warm-ink background, one verdigris-teal primary, and one accent that warms sage→honey→terracotta as a number rises. Editorial display type for the wordmark and a big hero number; clean sans for body. Single hero element (a soft aging ring or large numeral), generous whitespace, hairline separators, large radii, flat (no shadows/gradients/neon). Layout top→bottom: wordmark "Patina" + tagline "See your battery age, honestly."; hero "Aging speed ≈ 1.7×" with caption "aging vs an ideal idle (25°/50%)", a cause line, and a small "relative estimate — not a capacity measurement" label; a tiny row of 3 live drivers (cell temp, charge %, charging on/off); a "this week" strain line "1.4× ideal · +2.6 aging-days" with a 7-day sparkline; an outlook line "~80% health in 8–14 months"; one optional gentle action. Keep it simple — not a cockpit. Provide a "Details" section (collapsed) for an hour-of-day heat heatmap, a heat-vs-health note, a projection chart, and longevity factors.
