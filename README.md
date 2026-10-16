# IMDenza

3333 fully on-chain, animated, generative flow-field pieces on Ethereum mainnet (chain id 1).
ERC721C (Limit Break creator-token-standards v4.0.1) with 6.9% creator earnings, no owner, no pause,
no upgrade, and no mint path other than the three on-chain-checked free claims and the public mint.

Every piece is an SVG with CSS keyframe animation produced entirely by the contracts: thick curved
strokes grown along a seeded, noise-perturbed vector field with collision control, probabilistic
palettes, scale/turbulence/density variation, accent marks for swarm job categories and faint
structural traces left by the first swarm jobs.

## Contracts (`src/`)

| Contract | Role | Constructor arguments |
| --- | --- | --- |
| `SwarmHistory` | Permissionless, append-only commitment of IMD swarm job history (entropy, counters, decaying pulse). | none |
| `IMDenzaField` | Pure flow-field tracer: writes SVG `<path>`/`<use>` elements from seeded parameters. | none |
| `IMDenzaRenderer` | Traits, palettes, CSS animation, accents, traces, JSON metadata (base64 data URIs). | `swarm`, `field` |
| `IMDenza` | The ERC721C collection: claims, public mint, proceeds split, royalties, views. Creates its `IMDenzaDistributor` in its constructor. | `configurator`, `renderer`, `swarm` |
| `IMDenzaDistributor` | Pro-rata holder payouts for mint proceeds and royalties (ETH and any ERC-20). Created by `IMDenza`; address via `IMDenza.distributor()`. | none (binds to its creator) |

Launch manifest order and arguments (the manifest step writes `launch.json`; nothing here does):

1. `SwarmHistory` — `[]`
2. `IMDenzaField` — `[]`
3. `IMDenzaRenderer` — `[$contract:SwarmHistory, $contract:IMDenzaField]`
4. `IMDenza` — `[$owner, $contract:IMDenzaRenderer, $contract:SwarmHistory]`

`$owner` (0x3d6a89c8751a45dd577a4c1f3b34e71c58236193) is the **configurator**: its single power is to
set the Identity MD NFT collection address once (see "After launch"). It cannot pause, mint, upgrade,
change fees, move funds or change any other setting. No contract exposes `owner()`.

All constructors are nonpayable, make no external calls (ERC721C's base constructor only calls the
validator if it has code, inside try/catch) and succeed on an empty chain. Runtime sizes are under
24,576 bytes (`forge build --sizes`); `IMDenza` init code is ~21 KB including the distributor.

## Minting

Supply is capped at 3333 across all routes; every route reverts with `SoldOut` after the last piece.
Each route is checked on chain at mint time; there is no allowlist or signature.

| Route | Function | Check | Limit |
| --- | --- | --- | --- |
| Identity MD holder | `claimWithIdentityMd(identityTokenId)` | `ownerOf(identityTokenId) == msg.sender` on the configured collection | 1 per wallet **and** 1 per Identity MD NFT |
| IMD holder | `claimWithImd()` | balance strictly greater than 25 whole tokens in either IMD token (decimals read from the token; more than 36 decimals never qualifies) | 1 per wallet |
| Fidenza holder | `claimWithFidenza(fidenzaTokenId)` | token id in project 78 (78000000–78999999) and `ownerOf == msg.sender` on Art Blocks `0xa7d8…d270` | 1 per wallet **and** 1 per Fidenza |
| Public | `mint(paymentToken)` | pulls 0.069 IMD (`MINT_PRICE_MILLI = 69` thousandths, scaled by the token's decimals) via `transferFrom`; reverts `UnderPaid` unless at least the price arrives, and `UnsupportedDecimals` for a token with fewer than 3 or more than 36 decimals (the price would truncate or overflow) | unlimited until sold out |

The three free routes are independent: a wallet that qualifies for all three can claim three pieces.
Public mint proceeds are measured as the balance actually received (fee-on-transfer safe): 90% is sent
to the distributor and attributed immediately to all minted tokens including the new one (so the
first public minter's own piece receives 90% of its payment back, the second 45%, and so on: a reading
of "pro-rata to holders" the requester may want to confirm); 10% is sent to the treasury
`0xc3F0dEC012784f6d7178104C31A4611c6897756c`.

Token hash: `keccak256(tokenId, blockhash(block.number-1), prevrandao, minter, block.number, timestamp)`,
the Art Blocks style "mint transaction" hash. A hash already seen is re-hashed until unused.
The swarm state a mint snapshots is the ledger as it stood at the end of the previous block
(`SwarmHistory.snapshot()`): records made in the mint's own block, including inside the mint
transaction, only count for later blocks, so a minter cannot reroll its composition by appending junk
records. Because the brief bases the seed on the mint transaction, a minting contract can still compute
its own token hash in advance and choose whether (and from which address) to mint; that selection is
inherent to a mint-transaction seed and only changes which artwork a minter gets.

## Generative system and uniqueness

* Composition seed `S = keccak256(tokenHash, swarmEntropyAtMint, tokenId)`. The token id is part of
  the preimage, so two tokens can only share `S` through a keccak collision. `IMDenza` also records
  `seedUsed[S]` and refuses a duplicate, and refuses a reused token hash. Every byte of the artwork
  except the live pulse is a pure function of `S`, the mint snapshot and the immutable foundational
  job digests, so any piece can be regenerated forever by calling `IMDenza.svg(tokenId)` or by
  re-running the same pure code with `IMDenza.tokenData(tokenId)`.
* Traits (`IMDenza.traits(tokenId)` / `IMDenzaRenderer.traits(piece)`): scale (Small/Medium/Large/Jumbo),
  turbulence (None/Low/Mid/High), density (Sparse/Medium/Dense), palette family (8), collision mode
  (Tight/Standard/Airy), outline, base angle, accent marks, foundational traces, contributing job range
  (`0 .. swarmJobIndex-1`), live pulse and pulse influence (0–100). Scale, turbulence and density
  probabilities are biased by the swarm entropy bytes; the favoured palette family comes from the
  swarm entropy.
* Field: value-noise lattice (seeded), bilinear + smoothstep, angle = base + noise swing; strokes are
  grown step by step and stop at the canvas bound or when they would touch an occupied cell of a
  96×96 collision grid (gap by collision trait). Up to 1200 start points are tried per piece to reach
  the shape budget (45/80/120).
* Animation (CSS): gentle flow along each stroke's own direction (`translate` with per-shape vars),
  breathing of stroke widths, density change (every fifth stroke fades), hue/saturation drift on the
  root group, and pulsing accent marks. The swarm **pulse** (recent activity, decays by
  `PULSE_DECAY_PER_BLOCK` = 138 per block, so a saturated pulse is idle after 7247 blocks) scales animation speed (up to 2×), breathing amplitude (6%→20%), flow amplitude and
  saturation. It never changes the composition; once decayed the exact original bytes return.
* Swarm history: `SwarmHistory` is the "compact committed summary updated permissionlessly" the brief
  allows. Anyone appends a record (`recordJob` / `recordJobs`, unique job id, category 0–7, agent
  count, outcome, timestamp ≤ now for back-fill since block 0). Each record folds into a rolling
  entropy hash, category counters and the pulse. A mint snapshots `entropy`, `jobCount` and the
  category profile; categories present add accent marks (circle, ring, square, bar, triangle,
  diamond, cross, dot in fixed accent colours); the first 16 records are "foundational" and leave
  low-opacity structural lines in every piece minted after them.

## Distribution (`IMDenzaDistributor`)

* Receives ETH (`receive()`), IMD mint proceeds and any ERC-20 royalty (OpenSea pays ETH or WETH).
* `distribute(asset)` (permissionless) attributes the unattributed balance equally to every token minted
  so far, recording a `(mintedCount, accumulator)` checkpoint; with nothing new it is a no-op returning 0.
  Before every mint, `IMDenza` calls `sync([ETH, IMD A, IMD B, WETH])`, which does the same for those
  assets (skipping any it cannot read), so value that arrived before a piece existed is never shared
  with it, whether or not anyone called `distribute`. Any other ERC-20 sent here is attributed only when
  someone calls `distribute(thatToken)`, to the pieces that exist at that moment. A mint attempted from
  inside a distributor payout reverts (the distributor's reentrancy guard refuses the sync). `claim(asset, tokenIds)` pays the
  pending amount of the listed tokens (all owned by one wallet) to their **current owner**; anyone may
  trigger it. Unclaimed value travels with the token. Pieces minted later never share earlier
  distributions (binary search over checkpoints; no transfer hooks, no unbounded loops).
* Rounding: each distribution credits `floor(amount·1e18/minted)` units per token and reserves the
  credited total rounded up to whole wei; the unreserved remainder joins the next distribution. A claim
  pays each token its whole-wei share and keeps the fraction credited to it, so `pending()` and `claim()`
  agree and claims can never exceed `reserved`. At most 1 wei per distribution stays locked as dust.
  A receiver that rejects ETH only blocks its own claim.
* Royalties: `royaltyInfo` returns `(distributor, 6.9%)` for every token. `IMDenza` applies the
  ERC721C policy on Limit Break's default validator (`0x721C002B…cd1B`, live on mainnet): security
  level 3 (operator whitelist, OTC allowed) with whitelist id 0 (Limit Break's default list).
  This happens automatically at the first mint (best effort) and can be re-applied by anyone with
  `applyTransferPolicy()` (strict: reverts if the validator has no code or rejects the call).

## After launch

| Setting | Setter | Value | Where the owner gets it |
| --- | --- | --- | --- |
| Identity MD NFT collection | `IMDenza.setIdentityMdCollection(address)` from the configurator wallet, once | the mainnet address of the Identity MD ERC-721 collection | the Identity MD project's deployment records; the brief named the collection but not its address |

Until it is set, `claimWithIdentityMd` reverts with `NotConfigured`; every other route works. The
setter refuses (and stays usable after) an address without code (`NoCode`), a contract that does not
report ERC-721 through ERC-165 (`NotErc721`), and IMDenza itself, its distributor or the Art Blocks core
(`InvalidCollection`). It cannot tell the real Identity MD collection from another ERC-721: the
configurator could still point the route at a collection it controls, which is the one trust assumption
of this role; holders can read `identityMdCollection()` and the `IdentityMdCollectionSet` event.

Operational responsibilities (no key is needed for any of them, anyone may do them):

* Back-fill the swarm history (`recordJobs`, ≤200 per call) **before** minting opens if the brief's
  "since block 0" history should influence the earliest pieces; later records only affect later mints
  and the live pulse. Record ongoing jobs as they complete.
* Call `applyTransferPolicy()` once after launch and confirm on OpenSea that creator earnings show as
  enforced (the first mint attempts it automatically; the explicit call reverts loudly if it failed).
* Call `IMDenzaDistributor.distribute(asset)` when royalties arrive (ETH or WETH), then holders claim.
  (Every mint also does this for ETH, IMD and WETH; after sell-out nobody new can dilute, so timing only
  matters for other ERC-20s.)
* Verify the sources on Etherscan with `forge verify-contract` (solc 0.8.26, optimizer 200 runs,
  via-IR, no metadata hash) — this is the launch deployer's step; this repository broadcasts nothing.

## Assumptions and open points

* **IMD token B** (`0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127`) has no code on mainnet at the time of
  writing (checked via a public RPC on 2026-10-16). It is kept as a constant and checked on use: it
  counts for the holding check only if it has code, and `mint()` with it reverts with `NoCode` until it
  does. IMD token A (`0xd34a…63b7`, "Identity.md", 18 decimals) is live.
* The mint price is paid in IMD (either token), 0.069 whole tokens; the price scales with the token's
  `decimals()`.
* Holding checks are point-in-time at the mint transaction: flash-loaned IMD or a borrowed Fidenza
  passes the balance/ownership check. Per-wallet flags and per-NFT reuse flags limit this to one claim
  per NFT and per wallet. The IMD route is per wallet, as the brief states, and the IMD itself is not
  locked or remembered: the same 26 IMD moved through fresh wallets (or contracts) claims once per
  wallet, so one actor holding 26 IMD can claim many free pieces for gas only, up to the remaining
  supply. Binding the IMD (escrowing 25 IMD for a lock period, or a pre-launch balance snapshot) would
  change the claim from "holds" to "locks" and needs the requester's decision; rejecting contract
  callers does not help (a contract claims from its constructor) and would shut out smart wallets.
* `SwarmHistory` is permissionless by design (the brief gave no on-chain job registry). Anyone can
  append records; this only changes entropy, counters and the pulse — never funds. It is first-come:
  whoever records first after deployment defines the 16 foundational records, a job id recorded with
  wrong data can never be corrected, and junk records can hold the pulse at its maximum. The operator
  should back-fill in the deployment's first blocks; nothing on chain enforces it.
* The token hash uses previous block hash and `prevrandao`; a builder can bias it, which only
  changes which artwork a minter gets, never uniqueness or value flows.
* `tokenURI` is a heavy view: Small-scale Dense pieces cost up to ~50M gas (an independent sample of
  300 pieces measured 49.5M at worst, about one piece in five above 30M). Geth's default `eth_call`
  cap is 50M and several hosted RPCs cap lower, so marketplaces and indexers need an RPC whose cap is at
  least 60M for every piece to render on chain; any piece can also be re-rendered off chain from
  `tokenData(tokenId)` with the same pure code.
* Unresolved for the requester: nothing blocking. The only value not in the brief (Identity MD
  collection address) is the one-shot setting above.

## Security notes

* No `delegatecall`, `selfdestruct`, proxies or `tx.origin`. Reentrancy guards on every mint and on
  the distributor's `distribute`/`sync`/`claim`; checks-effects-interactions throughout; `SafeERC20` for tokens.
* Trust: the configurator can only choose the Identity MD collection (and only once). Limit Break's
  validator and list 0 are external dependencies for marketplace enforcement; if that validator were
  ever removed, `applyTransferPolicy` reverts and transfers would revert (`ERC721C` calls it on every
  transfer) — the same dependency every ERC721C collection has.
* Tests (`test/`): 65 tests including fuzzing of fund conservation, entropy order sensitivity and
  rendering for arbitrary seeds. They are not an audit; an independent adversarial review is still
  required before real funds flow.

## Development

```
forge build
FOUNDRY_FUZZ_SEED=0x445d8f1782adf41168d3065d14d9794e9a87339049d65cb5e28bbe02ec6c7d54 forge test
forge fmt --check
```

Dependencies are vendored as plain files under `lib/` (forge-std, OpenZeppelin 4.8.3, Limit Break
creator-token-standards v4.0.1 subset, a minimal PermitC constants file). No submodules, no network
needed to build.
