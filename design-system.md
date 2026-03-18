# Design System Reference

All UI work must follow this established design system, shared across runeval and groceryGenius.

## Typography
- **Display font:** Fraunces (serif, weights: 400-700)
- **Body font:** IBM Plex Sans (sans-serif, weights: 400-700)
- **Mono font:** IBM Plex Mono (code blocks)
- Load from Google Fonts. Use CSS classes `font-display` for headers, `font-body` for body text.

## Color Palette (Warm Earth Tones)
| Token | Hex | Usage |
|-------|-----|-------|
| Ink | #1b1b1b | Primary text, dark elements |
| Sand | #f3efe6 | Page background, light accent |
| Ember | #e85d2f | Primary accent, CTAs, highlights |
| Moss | #436a5a | Secondary accent, success states |
| Sky | #c9d6df | Tertiary accent, borders, muted elements |
| Card BG | rgba(250,250,248,0.88) | Card backgrounds (glass effect) |
| Destructive | #dc2626 | Error states, destructive actions |

## Visual Style
- **Light mode only.** Warm, airy aesthetic. No dark mode.
- **Glass-morphism cards:** `bg-white/80 backdrop-blur-sm rounded-2xl border border-black/5 shadow-card`
- **Shadow:** `0 20px 45px -30px rgba(0,0,0,0.35)` for cards
- **Border radius:** 16px default (`rounded-2xl` for cards, `rounded-full` for buttons/badges)
- **Buttons:** `rounded-full` with border, pill-shaped
- **Badges:** `rounded-full` uppercase tracking

## CSS Framework
- **Tailwind CSS** (utility-first)
- Define custom colors, fonts, and shadows in `tailwind.config.*`
- Use `cn()` utility (clsx + tailwind-merge) for conditional classes

## Component Patterns
- **Preferred:** Radix UI primitives + shadcn/ui pattern (CVA variants)
- **Icons:** Lucide React
- **Forms:** React Hook Form + Zod validation
- **Charts:** Recharts with palette colors (ember, moss, sky, ink, sand)
- **Animation:** tailwindcss-animate (subtle transitions, no flashy effects)

## Layout
- **Header:** Top navigation bar, max-w-6xl or max-w-7xl, horizontal menu
- **Content:** Card grid layouts with consistent gap spacing
- **Mobile:** Responsive flex/grid, tab-based navigation on mobile
- **Background:** Radial + linear gradient combination (subtle warm gradient)

## Rules for UI Changes
1. Match existing color palette exactly. Don't introduce new colors without justification.
2. Use Fraunces for headings, IBM Plex Sans for body. No other fonts.
3. Cards must have the glass-morphism effect (backdrop blur + semi-transparent bg).
4. Buttons are always pill-shaped (rounded-full).
5. Keep the warm, minimal aesthetic. No heavy borders, no dark backgrounds.
6. If a project doesn't have these styles yet, add them as part of the improvement.
7. Reference groceryGenius `/components/ui/` for the canonical component implementations.
