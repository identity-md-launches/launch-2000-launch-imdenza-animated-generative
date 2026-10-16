import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  client,
  readCollection,
  COLLECTION,
  collisionNames,
  densityNames,
  paletteNames,
  scaleNames,
  turbulenceNames,
  type CollectionState,
} from './chain'
import {
  Art,
  Arrow,
  ErrorNotice,
  External,
  Loading,
  Modal,
  MotionButton,
  usePiece,
  useSvg,
} from './components'
import { explorer, number, opensea } from './format'

export function PiecePage({
  id,
  state,
}: {
  id: number
  state?: CollectionState
}) {
  const valid = Number.isInteger(id) && id > 0 && id <= 3333
  const query = usePiece(id)
  const svg = useSvg(id, valid && (!state || id <= state.minted))
  const [expanded, setExpanded] = useState(false)
  const [copied, setCopied] = useState(false)
  const [copyError, setCopyError] = useState(false)
  const piece = query.data
  const mint = useQuery({
    queryKey: ['mint-tx', id, piece?.data.mintBlock],
    enabled: !!piece,
    queryFn: async () => {
      const logs = await client.getContractEvents({
        ...readCollection,
        eventName: 'Minted',
        args: { tokenId: BigInt(id) },
        fromBlock: BigInt(piece!.data.mintBlock),
        toBlock: BigInt(piece!.data.mintBlock),
      })
      return logs[0]?.transactionHash ?? null
    },
    staleTime: Infinity,
    retry: 1,
  })
  if (!valid || (state && id > state.minted))
    return (
      <div className="page empty-state">
        <h1>This piece hasn’t been minted.</h1>
        <p>Explore the works that already exist, or mint a new composition.</p>
        <a className="button" href="#/gallery">
          Explore the collection <Arrow />
        </a>
      </div>
    )
  function download() {
    if (!svg.data) return
    const url = URL.createObjectURL(
      new Blob([svg.data.svg], { type: 'image/svg+xml' }),
    )
    const a = document.createElement('a')
    a.href = url
    a.download = `IMDenza-${id}.svg`
    a.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }
  return (
    <div className="page piece-page">
      <div className="piece-top">
        <a href="#/gallery" className="text-button">
          <span aria-hidden="true">←</span> Back to collection
        </a>
        <div className="piece-nav">
          <a
            className={`icon-button ${id <= 1 ? 'disabled-link' : ''}`}
            aria-label="Previous piece"
            aria-disabled={id <= 1}
            href={id > 1 ? `#/piece/${id - 1}` : undefined}
          >
            ←
          </a>
          <span>#{String(id).padStart(4, '0')}</span>
          <a
            className={`icon-button ${!state || id >= state.minted ? 'disabled-link' : ''}`}
            aria-label="Next piece"
            aria-disabled={!state || id >= state.minted}
            href={state && id < state.minted ? `#/piece/${id + 1}` : undefined}
          >
            →
          </a>
        </div>
      </div>
      <div className="piece-layout">
        <div className="piece-view">
          <Art id={id} priority />
          <div className="art-controls">
            <MotionButton />
            <button className="text-button" onClick={() => setExpanded(true)}>
              Expand view <Arrow diagonal />
            </button>
          </div>
          <p className="small muted">
            {svg.data ? (
              <>
                On-chain SVG read at{' '}
                <External href={explorer('block', svg.data.block)}>
                  block {number(BigInt(svg.data.block))}
                </External>
              </>
            ) : (
              'Fetching the animated SVG directly from the collection contract.'
            )}
          </p>
          {svg.isError && (
            <ErrorNotice error={svg.error} retry={() => svg.refetch()} />
          )}
        </div>
        <div className="piece-info">
          <h1>
            IMDenza <span>#{String(id).padStart(4, '0')}</span>
          </h1>
          <p className="piece-subtitle">A unique field. A permanent trace.</p>
          {query.isPending && <Loading>Reading this piece’s traits…</Loading>}
          {query.isError && (
            <ErrorNotice error={query.error} retry={() => query.refetch()} />
          )}
          {piece && (
            <>
              <dl className="traits">
                {[
                  ['Palette', paletteNames[piece.traits.palette]],
                  ['Scale', scaleNames[piece.traits.scale]],
                  ['Turbulence', turbulenceNames[piece.traits.turbulence]],
                  ['Density', densityNames[piece.traits.density]],
                  ['Collision', collisionNames[piece.traits.collision]],
                  ['Outline', piece.traits.outline ? 'Yes' : 'No'],
                  ['Pulse influence', `${piece.traits.pulseInfluence}%`],
                  [
                    'Contributing job range',
                    piece.traits.jobsTo === 0n
                      ? 'None recorded at mint'
                      : `0–${piece.traits.jobsTo - 1n}`,
                  ],
                  ['Foundational traces', String(piece.traits.traces)],
                  ['Accent marks', String(piece.traits.accents)],
                ].map(([label, value]) => (
                  <div key={label}>
                    <dt>{label}</dt>
                    <dd>{value}</dd>
                  </div>
                ))}
              </dl>
              <div className="provenance">
                <h2>Provenance</h2>
                <label>Mint hash</label>
                <p className="hash">{piece.data.tokenHash}</p>
                <p className="small muted">
                  The contract’s mint-context hash seeds this composition. The
                  Ethereum transaction hash is linked separately below.
                </p>
                <label>Current owner</label>
                <External
                  className="hash"
                  href={explorer('address', piece.owner)}
                >
                  {piece.owner}
                </External>
                <div className="provenance-links">
                  {mint.data ? (
                    <External href={explorer('tx', mint.data)}>
                      Mint transaction
                    </External>
                  ) : (
                    <External href={explorer('block', piece.data.mintBlock)}>
                      Mint block {number(piece.data.mintBlock)}
                    </External>
                  )}
                  <External
                    href={`https://etherscan.io/nft/${COLLECTION}/${id}`}
                  >
                    Token on Etherscan
                  </External>
                </div>
              </div>
              <details className="seed-details">
                <summary>Composition seed & swarm entropy</summary>
                <label>Composition seed</label>
                <p className="hash">{piece.traits.seed}</p>
                <label>Swarm entropy at mint</label>
                <p className="hash">{piece.data.swarmEntropy}</p>
              </details>
            </>
          )}
          <div className="piece-actions">
            <External className="button" href={opensea(id)}>
              View on OpenSea
            </External>
            <button
              className="button secondary"
              disabled={!svg.data}
              onClick={download}
            >
              Download animated SVG
            </button>
            <button
              className="text-button"
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(location.href)
                  setCopied(true)
                  setCopyError(false)
                } catch {
                  setCopyError(true)
                }
              }}
            >
              {copied ? 'Link copied' : 'Copy piece link'} <Arrow diagonal />
            </button>
            {copyError && (
              <p className="small" role="status">
                Copy the page URL from your browser’s address bar.
              </p>
            )}
          </div>
        </div>
      </div>
      <Modal
        open={expanded}
        onClose={() => setExpanded(false)}
        title={`IMDenza #${String(id).padStart(4, '0')}`}
        className="art-modal"
      >
        <Art id={id} priority />
        <MotionButton />
      </Modal>
    </div>
  )
}
