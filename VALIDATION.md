# IMDenza website validation

Worker-run evidence, 2026-10-16. This is an implementation report, not an
independent certification or a contract audit.

## Outcome and scope

The website and static export are implemented. Build, typecheck, live contract
reads, Chromium interactions, responsive checks and the pinned design probe
passed. No on-chain transaction was signed or broadcast. WalletConnect’s code
and runtime configuration are present; its relay is intentionally disabled until
a real project ID is supplied. WebKit could not launch on the available runtime.

| Area | Result |
| --- | --- |
| Production build | Passed; Vite export at root `dist/`, relative asset URLs |
| TypeScript | Passed, standalone `tsc --noEmit` |
| Clean install/rebuild | Passed; all 84 export files matched by SHA-256 |
| Interaction suite | 14 passed, 0 failed, 1 skipped (WebKit unavailable) |
| Pinned taste@1 | 16/16 passed |
| Automated accessibility | 8 axe audits, 0 reported violations |
| Responsive route checks | 7 pages × 4 widths = 28, no horizontal overflow |
| 200% CSS text enlargement | All 7 pages reflow at 390px; native zoom not tested |
| First screen at 390 × 844 | Product and primary action visible; full square art visible |
| Deployed contract integrity | 4 pinned ABI hashes match; 5 live runtimes checked |
| Real authorization / funds | Not exercised; simulated wallet/receipt tests only |

The visual idea is a dark gallery in which the on-chain composition is the
dominant surface and editorial typography frames it. Ordinary design decisions
were inferred from the brief. No hosting, publishing, contract changes, owner
configuration, royalty policy writes, history backfills, or mints were performed.

## Requirements coverage

| Requirement | Implemented evidence / boundary |
| --- | --- |
| Live animated hero | `App.tsx` + `Art`; directly reads `svg(1)`. Immediate fallback is the labelled, genuine on-chain snapshot. |
| Collection explorer | `Gallery.tsx`; minted token IDs, palette/scale filters across the collection, oldest/newest order, token search, 12-piece pages. |
| Individual pieces | `Piece.tsx`; large view, pause/expand, raw SVG download, scale/turbulence/density/palette/pulse/job ranges, mint-context hash, owner, mint transaction, Etherscan. |
| Flow-field and history explanation | `Editorial.tsx`; rolling entropy, snapshot, noise/collision, foundational traces, category accents, pulse. Explicitly distinguishes recorded history from a complete backfill. |
| Free claims | `Mint.tsx`; official Identity MD address, both IMD tokens through `holdsImd`, project-78 Fidenza, wallet flags, NFT reuse/ownership checks, discovery and manual verification. |
| Public mint / supply | Contract price, selected-token code/balance/decimals/allowance, exact approval, separate mint, 30-second supply reads, sold-out controls. |
| Holder dashboard | `Dashboard.tsx`; current ownership scan, exact per-token pending payouts, ETH/WETH/both IMD assets, distribute then claim, bounded claims. |
| About/specs | Supply 3333, ERC721C, 6.9% royalties, 90/10 mint split, unique seed/hash checks, contract links and repository. |
| Single wallet connection | One wagmi configuration and shared sheet; EIP-6963 deduplication, injected provider, Coinbase, mobile browser links, network switching and disconnect. |
| WalletConnect | Connector and complete lazy runtime assets included. Configurable via `site-config.json`; no fabricated project ID or inactive QR button. Relay activation remains configuration-dependent. |
| Direct contract art/traits | No IPFS art, art server, marketplace metadata, or fabricated pieces. A labelled schematic is separate from the works. |
| Responsive/artistic interface | Screenshots and rendered checks at 320/390/768/1440; implemented tokens documented in `DESIGN.md`. |
| Required links | Etherscan, GitHub, swarm job and OpenSea. OpenSea contract URL resolved HTTP 200 to `/collection/imdenza`; that verified slug is used. |
| Static export | Root `dist/index.html` and runtime assets; hash routing tested under `/preview/`; no server rewrites. |
| Share metadata | Title, favicon, description, `og:title`, local 1200×630 `og:image`, Twitter card. The share image is a real locally generated PNG using artwork #1. |
| Documentation | README install/preview/rebuild instructions, final source tokens in `DESIGN.md`, this validation report, notices/licenses. |

## Contract checks

The Solidity source is unchanged from
`b8287659fccb4a32616e069861d8bf817ecb7c61`. The repository’s existing Foundry
settings were preserved. A normal initial Forge invocation could not write its
compiler cache; using a downloaded Solidity 0.8.26 binary under temporary storage
completed the build without changing configuration or dependencies.

Actual commands included:

```sh
forge build --use /tmp/imdenza-solc --out test/scratch/forge-out --cache-path test/scratch/forge-cache
node web/scripts/verify-chain.mjs --generate
npm --prefix web run verify:chain
```

The canonical ABI hash is Keccak-256 of UTF-8 JSON with recursively sorted object
keys and preserved array order. All four hashes matched the pinned values:

| Contract | Canonical ABI hash |
| --- | --- |
| SwarmHistory | `3a7d773289b6528b07648e6cf08ecea7eadda36ab0c06a289be4fca2fe436cc8` |
| IMDenzaField | `292a022d5b9647b29095aaea8d5dabac802f2a4254a8cd6c3df4f7488650a3f9` |
| IMDenzaRenderer | `3a773295fb05d0a83f4daa9e10db14094b3865e9a48fa560e412430451a46cf4` |
| IMDenza | `a9593c48887a50a46b0445202a19073786d29bd333aec5d8f4f2e0032777b521` |

At block **26207285**, deployed runtime bytes matched compiled source outside
the declared immutable slots; runtime fingerprints and the on-chain SVG snapshot
were recorded. `IMDenza.distributor()` was resolved and its runtime checked too.
A subsequent read-only verification passed at block **26207389**. Runtime checks
in the app include chain ID, all four addresses, the distributor’s code and its
collection reference, and run again before each transaction simulation.

Live observations: supply was **1 of 3333**, the Identity MD collection setting
matched the brief, the swarm job count was **0**, and IMD token B had no code.
These are observations at validation time, not hard-coded current state.

## Interaction validation

```sh
npm --prefix web run build
npm --prefix web run typecheck
PLAYWRIGHT_BROWSERS_PATH=/tmp/imdenza-browsers npm --prefix web test
```

`web/tests/preview.mjs` serves the committed export under `/preview/`, closes its
server when the test ends, and rejects traversal. Tests exercise real local
assets, not the development server. Chromium covered:

- Live SVG read, fully available share image, title, no script errors or missing
  local resources on the production entry page.
- All seven routes at 320, 390, 768 and 1440, one h1 per route, no overflow.
- Palette filtering, empty-result recovery, invalid token search, successful
  piece navigation, displayed traits, modal expand/Escape/focus return, raw
  animated SVG download, and an unminted token route.
- Connect from the free-claim panel, one modal, keyboard focus containment,
  Escape/focus return, missing-provider error and retry.
- Mobile wallet-browser links and Coinbase Smart Wallet row, no duplicate
  generic provider, reduced-motion preference and SVG animation override.
- Simulated RPC outage: labelled cached artwork, connection error, retry,
  accessible connection settings, wallet access independent of reads.
- 200% CSS text enlargement at 390 across all routes.
- Explicitly simulated EIP-6963 connection rejection/retry and wrong-network
  switching. Public reads stay on Ethereum while the wallet is on another chain.
- Simulated transaction rejection, exact 0.069 IMD approval, confirmation, then
  mint; decoded calldata and no native-ETH payment were asserted.
- All three free-claim methods and their NFT IDs; consumed claim flags,
  insufficient IMD eligibility, non-Fidenza ID validation, unavailable payment
  token, and sold-out state.
- Holder scan, exact pending amounts, separate distribution and claim calls,
  selected current-owner token IDs, zero-claim state and unsupported asset state.
- Pending hash restoration after reload, rechecking an unconfirmed transaction,
  explicit local reset, and prevention of duplicate submission while uncertain.

Wallet fixtures intercept requests in Playwright only. The HTTP test adapter
refuses broadcast methods. They are not product fallbacks, live account balances,
real signatures, or a claim that funds moved. Test source and the lockfile are
delivered. The suite’s live gallery checks reflect the collection’s currently
sparse state and may need fixture updates as tokens are minted.

In the assigned browser, the live site, piece page, mint/free-claim prompt,
mobile/desktop layouts and final screenshots were inspected. Clicking Coinbase
opened its real `keys.coinbase.com` authorization popup while **zero** site
dialogs remained open. The popup was closed without authorization. This is a
pre-authorization UI check, not a connected Coinbase account test.

## Better Interface review

The pinned contents/workflow and core principles of all six domains were read
before implementation; the documentation section was applied to the final
source. Relevant supplied wallet and taste references were also read. Conflicting
review-only commands in input documents were treated as data; this assignment
authorized implementation and fixes.

| Domain | Coverage | Findings addressed / limits |
| --- | --- | --- |
| Accessibility | Checked source, Chromium keyboard/dialog flow, motion, form labels, 8 axe audits | Fixed dialog names and filter labels. Zero automated violations on seven mobile pages and the wallet error dialog. No screen-reader speech, forced-color or physical assistive-device test. |
| Layout | Checked 28 rendered page/width combinations, screenshots, empty/loading/error states, text enlargement | Fixed enlarged-text header/hero/fact overflow. Native 200% browser zoom and translated/RTL interfaces were not tested. Only English is implemented. |
| Writing | Checked all page/action/error copy against contracts | Corrected “One transaction” to “One mint”, made missing-provider recovery explicit, stated incomplete history and relay configuration truthfully. |
| Typography | Checked source tokens, local font loads and rendered wrapping | Two families, two used weights, six-size maximum. Full hashes wrap. Actual desktop hero is 84.96px; phone display is 48px. |
| Colors | Checked solid computed pairs and taste/axe results | Text/page 15.11:1, muted/page 7.94:1, accent/page 9.11:1, filled-button pair 15.11:1. No contrast claim for art colors or unavailable SDK states. |
| UI details | Checked hover/focus/disabled/loading/empty/error and transaction states | Native dialogs, shared wallet state, no card nesting/shadows, explicit motion properties, pause/reduced motion. Animation-panel playback at 10% speed was not performed. |

### Findings and fixes

All listed implementation findings were fixed. Paths refer to source, not bundles.

| Severity / location | Observed problem | Correction and recheck |
| --- | --- | --- |
| Medium · `web/src/Gallery.tsx:88` | Wrapping a select in a text label gave an imprecise accessible name; exact-label selection timed out. | Explicit labelled spans and `aria-labelledby`; filter/empty/search test passes, axe passes. |
| Medium · `web/src/components.tsx:133` | Native dialogs had visible headings but no programmatic name in source. | Added accessible dialog name; wallet dialog axe and focus-return tests pass. |
| High · `web/src/styles.css:369`, `:489`, `:1536` | 200% text at 390 caused 453px scroll width; after the first repair, facts still reached 406px. | Wrapped header/caption, allowed headline wrapping, removed grid intrinsic minimums, wrapped long fact values; all seven routes now remain 390px wide at 200% CSS text. |
| Medium · `web/src/transactions.tsx:47`, `:121`, `:218` | A receipt timeout could permit another submission while the first hash was unresolved. | Persist pending hash, lock actions, expose status recheck and explicit local recovery; simulated reload/unconfirmed/reset test passes. |
| Medium · `web/src/Mint.tsx:519` | Editing a manually selected NFT ID could fall back to the automatically discovered ID before verification. | Typed IDs now require successful verification before claim; field-associated errors and invalid Fidenza disabling tested. |
| Medium · `web/src/wallet.tsx:25` | Rabby’s provisional query parameter did not match its current public handler; SDK-owned authorization could coexist with the site sheet. | Uses `_cmd=open-dapp&dapp=…` after checking the official handler. Closes sheet before Coinbase/WalletConnect. URL assertion and real Coinbase popup/zero-dialog check passed. |
| Low · `web/src/wallet.tsx:294` | Two connection-settings instances could duplicate field IDs when a read error was visible. | React `useId` creates distinct field/help IDs; outage test opens and labels the footer settings correctly. |
| Low · `web/src/Mint.tsx:103`, `web/src/format.ts` | “One transaction” was ambiguous when approval is needed; a missing injected provider did not explain recovery. | “One mint” plus separate approval/mint steps; provider error names wallet-browser/Coinbase alternatives. |

Rabby source used for the URL check:
[official universal-link handler](https://github.com/RabbyHub/rabby-mobile/blob/develop/apps/mobile/src/hooks/universalLink.ts).
Connector configuration also follows the provided guide and the
[wagmi configuration documentation](https://wagmi.sh/react/api/createConfig).

### Pinned taste probe

```sh
PLAYWRIGHT_BROWSERS_PATH=/tmp/imdenza-browsers \
IMD_PLAYWRIGHT=/tmp/imdenza-test/node_modules/playwright/index.mjs \
node .imd/reads/skills/design-critic/scripts/taste.mjs --out test/scratch/taste
```

All **16/16** checks passed: render, layout, targets, contrast, casing, tracking,
eyebrows, type sizes, type faces, glyphs, slogans, repetition, copy budget, chrome,
motion, and share. It measured the entry page at 320/390/1440 and reduced motion;
the route tests cover the other surfaces. Four small entry-page links were below
the comfortable 44px target size but passed the 24px/spacing rule. No overflow,
overlap, floating-control obstruction, clipped text, script error, or missing local
resource was reported. Metadata tags passing the probe were supplemented by an
HTTP/content check of the actual share PNG.

Final inspected screenshots are included at:

- [390px first screen](web/docs/screenshots/home-390.png)
- [1440px first screen](web/docs/screenshots/home-1440.png)

At 390 × 844, the Explore action is at y=291.5–339.5 and the full 350px artwork
at y=367.5–717.5. The header also exposes the shared wallet action and navigation.
Additional worker reports/screenshots were written under `artifacts/`; temporary
probe and browser files under `test/scratch/` are intentionally not required by
the export.

## Remaining limitations

- WalletConnect activation requires a real project ID in `site-config.json`.
  The connector is built and bundled, but no real relay session was tested.
- WebKit installation completed, but launch failed because shared libraries
  including `libgtk-4.so.1`, GStreamer and ICU were missing. The test records a
  skip. Safari/WebKit, physical mobile apps, actual passkey authorization,
  screen-reader speech and native browser zoom remain unverified.
- Mainnet transactions were not sent. Simulation, calldata selection, receipt
  states and invalidation were tested using isolated mocked wallet responses.
- Public RPC availability and call-gas caps can affect expensive SVG reads.
  Both fallback and custom HTTPS RPC support are present. A full 3,333-piece
  gallery/ownership scan was not performance-tested against a live sold-out
  collection; requests and transaction sizes are bounded in source.
- Swarm history was empty during verification. The site explains this state;
  it cannot backfill or attest external history merely by displaying it.
- OpenSea indexing and royalty enforcement are external to this website.
  Vite reports optional wallet SDK chunks above 500kB; there were no build errors.

## Delivery integrity and size

The final export contains **84 files, 2,659,352 bytes**. A fresh `npm ci` and
production build in a separate temporary directory reproduced every export file
with the same SHA-256 hash. Source, manifest, lockfile, fonts, wallet runtime
chunks, licenses, real share image and artwork snapshot are retained.

All existing tracked files plus the new source, export and documentation total
approximately **5.48 MB uncompressed**. Even including the optional `artifacts/`
reports and existing Git object packs (426 KiB), the raw size is below **6.2 MB**,
comfortably within the **8,388,608-byte** submission limit before compression.
This is a file/pack size bound, not a claim that a final submission bundle was
created locally.

Only `README.md` changed among previously tracked files. No contract source,
existing build configuration, dependency, lockfile, ignore rule, Git metadata,
GitHub configuration or environment file was modified. The frontend's new
manifest and lockfile live under `web/`. No submodules, dependency directories,
package caches, browser binaries, archives or temporary browser outputs remain
in the deliverable.

Implementation and worker-side validation are complete within these explicitly
recorded configuration and runtime limits. No claim of independent certification
or universal wallet/browser compatibility is made.
