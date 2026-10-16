# IMDenza design system

## Overview

IMDenza is an art collection and Ethereum application. Its interface uses a dark,
warm gallery setting, expressive serif headings, and quiet functional controls.
The on-chain SVG occupies the largest uninterrupted area on the home and piece
pages. There are no invented works, floor prices, activity feeds, or rarity scores.

The shared implementation is in `web/src/styles.css`, `components.tsx`, and
`wallet.tsx`. The home page pairs a six-word headline with a plain description,
an Explore action, a Mint link, and the actual first artwork. Other pages use
task-specific layouts rather than repeating the hero.

## Colors

The canonical format is hex. Primitives are mapped to semantic roles in
`web/src/styles.css:1`; components use the role tokens.

| Role token | Value | Use |
| --- | --- | --- |
| `--color-bg` | `#171916` | Page background and primary-button text |
| `--color-surface` | `#20231f` | Dialogs, inputs, payout panel, loading art |
| `--color-hover` | `#2b2e28` | Hovered neutral controls |
| `--color-border` | `#454940` | Structural rules and control borders |
| `--color-text` | `#f0ede4` | Primary text and filled primary actions |
| `--color-muted` | `#adafa2` | Captions, explanatory copy, field labels |
| `--color-accent` | `#e4af8c` | Hero emphasis, hover feedback, notices |
| `--color-success` | `#b7c99e` | Status dots and completed approval text |
| `--color-error` | `#f3aa9b` | Error text and error notice rule |
| `--color-focus` | `#f0ede4` | Visible keyboard focus perimeter |

Measured on the rendered home page: text/background **15.11:1**, muted text/page
**7.94:1**, accent/page **9.11:1**, primary button text/fill **15.11:1**. These
numbers describe those solid pairs, not the artwork’s colors. Status always has
text as well as a color. The site intentionally has one dark theme.

## Typography

- **Instrument Serif**, Georgia, serif: regular 400 for the wordmark and display
  headings; genuine 400 italic for “set in motion.” Local Fontsource assets.
- **DM Sans**, Arial, sans-serif: 400 body and labels, 500 buttons and emphasis.
  Local Fontsource assets; no external font service. Font synthesis is disabled.
- Six size roles: small `14px`, body `16px`, lead `20px`, title `28px`, section
  `48px`, display `88px`. At widths up to 1200px the display role is `72px`.
  At 680px and below, display is `48px` and section is `28px`.
- The home headline uses `clamp(48px, 5.9vw, display)` on large screens, and the
  display/section tokens at the smaller breakpoints. It measured `84.96px` at
  1440px. The rendered home used no more than six distinct sizes at any tested
  width.
- Heading line heights are `1.02`/`1.1`; body is `1.6`. Headings use balanced
  wrapping and tracking between `-.035em` and `-.02em`; body tracking is natural.
  The wordmark uses `-.04em`.
- Inputs stay at least `16px`. Counts and monetary values use tabular numbers.
  Hashes and addresses wrap with `overflow-wrap:anywhere`; full owner and
  provenance values remain selectable. The compact wallet control opens the
  complete checksummed address. Long editorial copy is limited to about 68ch.

## Layout

Spacing tokens are 8, 16, 24, 32, 48, 64, and 96px. Most surfaces group content
with space; rules separate navigation, collection facts, forms, and provenance.
The shared container is at most 1376px wide, with 56px side margins on large
screens, 32px below 1200px, 20px below 680px, and 16px below 360px.

- Home: two columns (`.91fr 1fr`) on desktop, text followed by art on mobile.
  At 390 × 844 the primary action starts at y=291.5 and the complete 350px-square
  artwork spans y=367.5–717.5. Both fit on the first screen.
- Gallery: three artwork columns, two below 960px, one below 680px. Filters
  appear above the results and wrap without horizontal scrolling. Pagination
  limits a page to twelve pieces.
- Piece: large art and a provenance/traits column. Art stays sticky on desktop;
  mobile places it before the details. Controls remain in normal document flow.
- Mint: artwork beside the controls on desktop. On mobile the mint controls
  precede the reference artwork, so price and wallet actions remain accessible.
- Dashboard: summary, payout controls, then owned works. Payout columns and
  summary rows stack on mobile. Claim batches contain at most 80 pieces.
- Editorial pages: maximum 1080px, with numbered explanations and concise specs.
- Below 960px navigation becomes a labelled menu toggle. Below 680px dialogs
  become bottom sheets. Header controls can wrap when text is enlarged.

Browsers were checked at 320, 390, 768, and 1440px. All seven pages passed reflow
at 390px with CSS text enlarged to 200%. That is not a native browser zoom test.

## Elevation & Depth

The system is flat: no decorative gradients, shadows, or nested cards. Art has
a low-opacity white 1px outline. Dialogs use the native top layer, a solid
surface, a structural border, and a `#0009` backdrop. Navigation’s mobile panel
uses z-index 10; the skip link uses 100 when focused. There are no fixed action
bars covering the artwork.

## Shapes

Artwork is square and uncropped. Buttons and fields have a 3px radius. Desktop
dialogs use 8px; mobile sheets use 12px at their top corners. Wallet icons use
6px. Status dots are circular. Structural separators are 1px; the mint progress
track is 3px.

## Components

| Component / pattern | Source | Behavior and reuse |
| --- | --- | --- |
| `Art`, `useSvg` | `web/src/components.tsx` | Direct contract SVG, lazy visibility, two-minute foreground refresh, fixed square layout, retry, explicitly labelled cached #1 fallback. SVG runs in an image context rather than injected page markup. |
| `MotionProvider`, `MotionButton` | `web/src/components.tsx` | Shared pause state; follows reduced-motion preference. Presentation-only SVG CSS pauses animation; downloads retain the original contract SVG. |
| `PieceCard` | `web/src/components.tsx` | Real anchor to a hash route, artwork, token number, and contract traits. No enclosing decorative card. |
| `.button`, `.secondary`, `.text-button`, `.icon-button` | `web/src/styles.css` | 48px main controls, 44px icon/text targets where practical; hover, focus, pressed and disabled states. One prominent filled action per primary surface. |
| `External` | `web/src/components.tsx` | External destination with an arrow and accessible new-tab announcement. |
| `Modal` | `web/src/components.tsx:105` | Native dialog with an accessible name, focus containment, Escape/backdrop/close dismissal and automatic focus return. Background scroll is locked while open. |
| `WalletProvider`, `WalletControl` | `web/src/wallet.tsx` | One shared connector configuration and sheet; named EIP-6963 providers, mobile app links, Coinbase and configured WalletConnect. Pending row, inline errors, network switching and disconnect. |
| `Notice`, `ErrorNotice`, `Loading` | `web/src/components.tsx` | Local, explicit statuses. Errors identify a recovery action. Loading uses a static dot rather than an endless spinner. |
| `TransactionStatus` | `web/src/components.tsx` | Simulation, wallet prompt, submitted hash, receipt, rejection/revert and uncertain-status recovery. No success before a confirmed successful receipt. |
| `ConnectionSettings` | `web/src/wallet.tsx:294` | Optional HTTPS RPC stored in the visitor’s browser; default restore and validation. Each instance has unique input IDs. |

Transitions name their properties and last 150ms. Press feedback scales controls
to `.96` only when reduced motion is not requested. Artwork is the only intended
continuous animation; the interface provides a visible pause control. Native
forms and selects carry keyboard behavior. Focus is a 2px visible outline with
4px offset. Every route has one h1 and the main landmark receives focus after
navigation.

## Do’s and don’ts

- Start a page with `.page` and `.page-heading`; use the existing type and color
  roles. Keep the body copy short and the art large.
- Use `PieceCard` for collection results and `Art` for the large viewer. Keep SVG
  output sourced from the contracts and distinguish cached reads from live reads.
- Use one existing wallet sheet. All transaction controls share the global
  transaction state and mainnet verification.
- Keep full hashes and addresses reachable and wrapping. Do not shorten them
  inside provenance, insert invented works, or imply the history is fully backfilled.
- Keep mobile controls within the page margins. Preserve normal vertical scrolling
  and enlarged-text wrapping; do not hide overflow to conceal layout defects.
- Add a hash route in `App.tsx`, reuse the shared primitives, and check its mobile,
  loading, empty, error, and keyboard states. Keep factual validation results in
  [VALIDATION.md](VALIDATION.md), rather than treating this design description as proof.

Design-guide attribution and licenses: [web/NOTICE.md](web/NOTICE.md).
