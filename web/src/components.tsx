import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  client,
  readCollection,
  getPiece,
  paletteNames,
  scaleNames,
  turbulenceNames,
} from './chain'
import { explorer, readableError } from './format'
import snapshot from './generated/snapshot.json'

export function Arrow({ diagonal = false }: { diagonal?: boolean }) {
  return (
    <svg
      aria-hidden="true"
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
    >
      <path d={diagonal ? 'M6 18 18 6M6 6h12v12' : 'M4 12h15m-6-6 6 6-6 6'} />
    </svg>
  )
}
export function External({
  href,
  children,
  className = '',
}: {
  href: string
  children: ReactNode
  className?: string
}) {
  return (
    <a
      className={`external ${className}`}
      href={href}
      target="_blank"
      rel="noopener noreferrer"
    >
      {children}
      <Arrow diagonal />
      <span className="sr-only"> (opens a new tab)</span>
    </a>
  )
}
export function Notice({
  children,
  error = false,
}: {
  children: ReactNode
  error?: boolean
}) {
  return (
    <div
      className={`notice ${error ? 'error' : ''}`}
      role={error ? 'alert' : 'status'}
    >
      {children}
    </div>
  )
}
export function Loading({
  children = 'Reading Ethereum…',
}: {
  children?: ReactNode
}) {
  return (
    <div className="loading" role="status">
      <span className="loading-dot" />
      {children}
    </div>
  )
}
export function ErrorNotice({
  error,
  retry,
}: {
  error: unknown
  retry?: () => void
}) {
  return (
    <Notice error>
      <p>{readableError(error)}</p>
      {retry && (
        <button className="text-button" onClick={retry}>
          Try again <Arrow />
        </button>
      )}
    </Notice>
  )
}
export function Modal({
  open,
  onClose,
  title,
  children,
  className = '',
}: {
  open: boolean
  onClose: () => void
  title: string
  children: ReactNode
  className?: string
}) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const dialog = ref.current
    if (open && dialog && !dialog.open) dialog.showModal()
    if (!open && dialog?.open) dialog.close()
    if (!open) return
    const previous = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.body.style.overflow = previous
    }
  }, [open])
  return (
    <dialog
      ref={ref}
      aria-label={title}
      className={`modal ${className}`}
      onCancel={(e) => {
        e.preventDefault()
        onClose()
      }}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose()
      }}
    >
      <div className="modal-inner">
        <div className="modal-head">
          <h2>{title}</h2>
          <button
            className="icon-button"
            aria-label={`Close ${title}`}
            onClick={onClose}
          >
            <svg
              aria-hidden="true"
              width="20"
              height="20"
              viewBox="0 0 24 24"
              stroke="currentColor"
              strokeWidth="1.5"
            >
              <path d="m6 6 12 12M6 18 18 6" />
            </svg>
          </button>
        </div>
        {children}
      </div>
    </dialog>
  )
}

const MotionContext = createContext({ paused: false, toggle: () => {} })
export function MotionProvider({ children }: { children: ReactNode }) {
  const [paused, setPaused] = useState(
    () => matchMedia('(prefers-reduced-motion: reduce)').matches,
  )
  useEffect(() => {
    const mq = matchMedia('(prefers-reduced-motion: reduce)')
    const update = () => setPaused(mq.matches)
    mq.addEventListener('change', update)
    return () => mq.removeEventListener('change', update)
  }, [])
  return (
    <MotionContext.Provider
      value={{ paused, toggle: () => setPaused((v) => !v) }}
    >
      {children}
    </MotionContext.Provider>
  )
}
export function MotionButton() {
  const { paused, toggle } = useContext(MotionContext)
  return (
    <button
      className="text-button motion-button"
      onClick={toggle}
      aria-pressed={paused}
    >
      {paused ? (
        <svg
          aria-hidden="true"
          width="16"
          height="16"
          viewBox="0 0 16 16"
          fill="currentColor"
        >
          <path d="m4 2 9 6-9 6z" />
        </svg>
      ) : (
        <svg
          aria-hidden="true"
          width="16"
          height="16"
          viewBox="0 0 16 16"
          fill="currentColor"
        >
          <path d="M3 2h3v12H3zm7 0h3v12h-3z" />
        </svg>
      )}
      {paused ? 'Play animation' : 'Pause animation'}
    </button>
  )
}
export function usePiece(id: number) {
  return useQuery({
    queryKey: ['piece', id],
    queryFn: () => getPiece(id),
    enabled: Number.isInteger(id) && id > 0 && id <= 3333,
    staleTime: 60_000,
    retry: 1,
  })
}
export function useSvg(id: number, enabled = true) {
  return useQuery({
    queryKey: ['svg', id],
    queryFn: async () => {
      const block = await client.getBlockNumber()
      const svg = await client.readContract({
        ...readCollection,
        functionName: 'svg',
        args: [BigInt(id)],
        blockNumber: block,
      })
      if (!svg.startsWith('<svg') || !svg.endsWith('</svg>'))
        throw new Error(
          'The renderer returned an unreadable artwork. Try again.',
        )
      return { svg, block: block.toString() }
    },
    enabled,
    staleTime: 120_000,
    refetchInterval: 120_000,
    refetchIntervalInBackground: false,
    retry: 1,
  })
}
export function Art({
  id,
  priority = false,
  className = '',
  onLive,
}: {
  id: number
  priority?: boolean
  className?: string
  onLive?: (live: boolean) => void
}) {
  const container = useRef<HTMLDivElement>(null)
  const [visible, setVisible] = useState(priority)
  const { paused } = useContext(MotionContext)
  const query = useSvg(id, visible)
  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setVisible(true)
          observer.disconnect()
        }
      },
      { rootMargin: '200px' },
    )
    if (container.current) observer.observe(container.current)
    return () => observer.disconnect()
  }, [])
  useEffect(() => onLive?.(!!query.data), [query.data, onLive])
  const source =
    query.data?.svg ?? (id === snapshot.tokenId ? snapshot.svg : undefined)
  const src = useMemo(
    () =>
      source
        ? `data:image/svg+xml;charset=utf-8,${encodeURIComponent(source.replace('</style>', `${paused ? '*{animation-play-state:paused!important}' : ''}@media(prefers-reduced-motion:reduce){*{animation:none!important}}</style>`))}`
        : undefined,
    [source, paused],
  )
  return (
    <div
      ref={container}
      className={`art ${className}`}
      aria-busy={query.isFetching}
    >
      {src ? (
        <img
          src={src}
          alt={`IMDenza #${id}, an on-chain animated flow-field composition`}
          fetchPriority={priority ? 'high' : 'auto'}
        />
      ) : (
        <div className="art-loading">
          {query.isError ? (
            <ErrorNotice error={query.error} retry={() => query.refetch()} />
          ) : (
            <Loading>Rendering artwork #{id}…</Loading>
          )}
        </div>
      )}
      {source && !query.data && (
        <span className="art-source">
          {query.isError
            ? 'On-chain snapshot · live read unavailable'
            : 'On-chain snapshot · updating'}
        </span>
      )}
    </div>
  )
}
export function PieceCard({ id }: { id: number }) {
  const piece = usePiece(id)
  return (
    <article className="piece-card">
      <a href={`#/piece/${id}`} aria-label={`View IMDenza #${id}`}>
        <Art id={id} />
        <div className="piece-caption">
          <h3>
            IMDenza <span>#{String(id).padStart(4, '0')}</span>
          </h3>
          <Arrow diagonal />
        </div>
      </a>
      <p className="piece-description">
        {piece.data
          ? `${paletteNames[piece.data.traits.palette]} · ${scaleNames[piece.data.traits.scale]} scale · ${turbulenceNames[piece.data.traits.turbulence]} turbulence`
          : 'Traits read directly from Ethereum'}
      </p>
    </article>
  )
}
export function TransactionStatus({
  status,
  hash,
  error,
  uncertain,
  check,
  resetPending,
}: {
  status: string
  hash?: string
  error?: unknown
  uncertain?: boolean
  check?: () => void
  resetPending?: () => void
}) {
  return (
    <div className="transaction-status" aria-live="polite">
      {status && (
        <Notice>
          <p>{status}</p>
          {hash && (
            <External href={explorer('tx', hash)}>View transaction</External>
          )}
          {uncertain && check && (
            <button className="button secondary full-width" onClick={check}>
              Check transaction status
            </button>
          )}
          {uncertain && resetPending && (
            <details>
              <summary>Transaction replaced or dropped?</summary>
              <p>
                Check the transaction in your wallet or on Etherscan. If it was
                replaced, cancelled, or dropped, clear this browser’s saved
                status to continue. Clearing the status does not cancel a
                pending transaction.
              </p>
              <button className="text-button" onClick={resetPending}>
                Clear local transaction status
              </button>
            </details>
          )}
        </Notice>
      )}
      {!!error && <ErrorNotice error={error} />}
    </div>
  )
}
