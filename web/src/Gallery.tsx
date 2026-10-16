import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  client,
  readCollection,
  paletteNames,
  scaleNames,
  type CollectionState,
} from './chain'
import {
  Arrow,
  ErrorNotice,
  Loading,
  MotionButton,
  PieceCard,
} from './components'
import { number } from './format'

export function Gallery({ state }: { state?: CollectionState }) {
  const [palette, setPalette] = useState('all')
  const [scale, setScale] = useState('all')
  const [sort, setSort] = useState('oldest')
  const [page, setPage] = useState(0)
  const [search, setSearch] = useState('')
  const [error, setError] = useState('')
  const [progress, setProgress] = useState(0)
  const filtered = palette !== 'all' || scale !== 'all'
  const index = useQuery({
    queryKey: ['trait-index', state?.minted],
    enabled: filtered && !!state,
    queryFn: async ({ signal }) => {
      const output: { id: number; palette: number; scale: number }[] = []
      const block = await client.getBlockNumber()
      for (let start = 1; start <= state!.minted; start += 40) {
        if (signal.aborted) throw new DOMException('Cancelled', 'AbortError')
        const batch = Array.from(
          { length: Math.min(40, state!.minted - start + 1) },
          (_, i) => start + i,
        )
        const traits = await Promise.all(
          batch.map((id) =>
            client.readContract({
              ...readCollection,
              functionName: 'traits',
              args: [BigInt(id)],
              blockNumber: block,
            }),
          ),
        )
        output.push(
          ...batch.map((id, i) => ({
            id,
            palette: traits[i].palette,
            scale: traits[i].scale,
          })),
        )
        setProgress(output.length)
      }
      return output
    },
    staleTime: Infinity,
    retry: 1,
  })
  useEffect(() => setPage(0), [palette, scale, sort])
  let ids = filtered
    ? (index.data ?? [])
        .filter(
          (t) =>
            (palette === 'all' || t.palette === Number(palette)) &&
            (scale === 'all' || t.scale === Number(scale)),
        )
        .map((t) => t.id)
    : Array.from({ length: state?.minted ?? 0 }, (_, i) => i + 1)
  if (sort === 'newest') ids = [...ids].reverse()
  const pages = Math.max(1, Math.ceil(ids.length / 12))
  return (
    <div className="page">
      <div className="page-heading row-between">
        <div>
          <h1>The collection.</h1>
          <p>Every field has a history. Find the one that moves you.</p>
        </div>
        <MotionButton />
      </div>
      <div className="gallery-toolbar">
        <div className="filters">
          <label>
            <span id="palette-label">Palette</span>
            <select
              aria-labelledby="palette-label"
              value={palette}
              onChange={(e) => setPalette(e.target.value)}
            >
              <option value="all">All palettes</option>
              {paletteNames.map((name, i) => (
                <option key={name} value={i}>
                  {name}
                </option>
              ))}
            </select>
          </label>
          <label>
            <span id="scale-label">Scale</span>
            <select
              aria-labelledby="scale-label"
              value={scale}
              onChange={(e) => setScale(e.target.value)}
            >
              <option value="all">All scales</option>
              {scaleNames.map((name, i) => (
                <option key={name} value={i}>
                  {name}
                </option>
              ))}
            </select>
          </label>
          <label>
            <span id="order-label">Order</span>
            <select
              aria-labelledby="order-label"
              value={sort}
              onChange={(e) => setSort(e.target.value)}
            >
              <option value="oldest">Oldest first</option>
              <option value="newest">Newest first</option>
            </select>
          </label>
        </div>
        <form
          className="piece-search"
          onSubmit={(e) => {
            e.preventDefault()
            if (
              !/^\d+$/.test(search) ||
              Number(search) < 1 ||
              Number(search) > (state?.minted ?? 0)
            ) {
              setError(
                `Enter a minted piece ID${state?.minted ? ` from 1 to ${state.minted}` : ' after supply loads'}.`,
              )
              return
            }
            setError('')
            location.hash = `/piece/${Number(search)}`
          }}
        >
          <label htmlFor="piece-search">Find a piece</label>
          <div className="input-action">
            <input
              id="piece-search"
              inputMode="numeric"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Token ID"
              aria-invalid={!!error}
              aria-describedby={error ? 'search-error' : undefined}
            />
            <button
              className="button secondary"
              type="submit"
              aria-label="Find piece"
            >
              <Arrow />
            </button>
          </div>
        </form>
      </div>
      {error && (
        <p className="error-text" id="search-error" role="alert">
          {error}
        </p>
      )}
      <div className="gallery-count">
        <span>
          {!state
            ? 'Reading the collection…'
            : filtered && index.isPending
              ? `Reading traits · ${number(progress)} / ${number(state.minted)}`
              : `${number(ids.length)} ${ids.length === 1 ? 'piece' : 'pieces'}${filtered ? ' matching your filters' : ` minted of ${number(state.max)}`}`}
        </span>
        {filtered && (
          <button
            className="text-button"
            onClick={() => {
              setPalette('all')
              setScale('all')
            }}
          >
            Clear filters
          </button>
        )}
      </div>
      {!state || (filtered && index.isPending) ? (
        <Loading>Reading artworks from Ethereum…</Loading>
      ) : index.isError && filtered ? (
        <ErrorNotice error={index.error} retry={() => index.refetch()} />
      ) : ids.length ? (
        <>
          <div className="gallery-grid">
            {ids.slice(page * 12, (page + 1) * 12).map((id) => (
              <PieceCard id={id} key={id} />
            ))}
          </div>
          {pages > 1 && (
            <div className="pagination">
              <button
                className="button secondary"
                disabled={page === 0}
                onClick={() => setPage((p) => p - 1)}
              >
                Previous
              </button>
              <span>
                Page {page + 1} of {pages}
              </span>
              <button
                className="button secondary"
                disabled={page + 1 >= pages}
                onClick={() => setPage((p) => p + 1)}
              >
                Next
              </button>
            </div>
          )}
        </>
      ) : (
        <div className="empty-state">
          <h2>
            {filtered
              ? 'No pieces match these filters.'
              : 'The first piece is waiting.'}
          </h2>
          <p>
            {filtered
              ? 'Try another palette or scale to explore the minted works.'
              : 'Mint a piece to begin the collection.'}
          </p>
          {filtered ? (
            <button
              className="button secondary"
              onClick={() => {
                setPalette('all')
                setScale('all')
              }}
            >
              Clear filters
            </button>
          ) : (
            <a className="button" href="#/mint">
              Mint a piece <Arrow />
            </a>
          )}
        </div>
      )}
      <div className="gallery-end">
        <p>New compositions appear as they are minted.</p>
        <a className="text-button" href="#/mint">
          Add your piece to the story <Arrow />
        </a>
      </div>
    </div>
  )
}
