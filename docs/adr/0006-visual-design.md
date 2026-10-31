# 0006. Visual design: market stall light, dark chocolate dark

- Status: Accepted
- Date: 2026-10-31

## Context
The first inventory screen looked generic. The owner wants an app that feels appetising to use. Three directions were mocked up (market stall, candy shop, dark chocolate); the market stall won.

## Decision
- **Light theme "market stall":** cream page (`base-200`), white cards (`base-100`), tomato red primary, olive green for selected states, warm shadows.
- **Dark theme:** the dark chocolate direction (brown surfaces, caramel primary), selected through the existing theme toggle.
- Colours live in the two daisyUI theme blocks in `assets/css/app.css`; components use the theme tokens (`bg-base-100`, `text-primary`, ...) and never hard-code colours, so both themes work everywhere.
- Fonts: Fraunces (display) and DM Sans (body), bundled as variable woff2 files in `priv/static/fonts`, not loaded from a CDN, so they also work offline.
- Items show an emoji tile (optional field on the item) or their first letter.
- Layout: mobile-first cards with large touch targets (at least 40px), bottom tab bar, pill shapes. daisyUI is used only for its theme tokens and basic form styling; app components are hand-written Tailwind.
- The `ash_authentication_phoenix` sign-in and sign-out pages are restyled through `KuraWeb.AuthOverrides`.

## Consequences
- New screens must follow the tokens and the card patterns in `KuraWeb.InventoryLive` and `KuraWeb.Layouts`.
- Two font files (about 70 KB) must be cached by the offline service worker in milestone 5.
