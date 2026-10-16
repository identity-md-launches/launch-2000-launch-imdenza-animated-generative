import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { collectionState, verifyDeployment, JOB, REPO } from './chain'
import {
  Art,
  Arrow,
  ErrorNotice,
  External,
  MotionButton,
  Notice,
  usePiece,
} from './components'
import { paletteNames, scaleNames, type CollectionState } from './chain'
import { ConnectionSettings, WalletControl } from './wallet'
import { number, opensea } from './format'
import { Gallery } from './Gallery'
import { Mint } from './Mint'
import { PiecePage } from './Piece'
import { Dashboard } from './Dashboard'
import { About, SystemIntro, SystemPage } from './Editorial'
import { useTransaction } from './transactions'

function useRoute() {
  const [route, setRoute] = useState(location.hash.slice(1) || '/')
  useEffect(() => {
    function change() {
      setRoute(location.hash.slice(1) || '/')
      window.scrollTo({ top: 0, behavior: 'instant' })
    }
    addEventListener('hashchange', change)
    return () => removeEventListener('hashchange', change)
  }, [])
  return route
}
export function App() {
  const route = useRoute()
  const [menuOpen, setMenuOpen] = useState(false)
  const collection = useQuery({
    queryKey: ['collection-state'],
    queryFn: collectionState,
    refetchInterval: 30_000,
    staleTime: 15_000,
    retry: 1,
  })
  const verification = useQuery({
    queryKey: ['deployment-verified'],
    queryFn: verifyDeployment,
    staleTime: 300_000,
    retry: 1,
  })
  const tx = useTransaction()
  useEffect(() => {
    setMenuOpen(false)
    const names: Record<string, string> = {
      '/gallery': 'The collection',
      '/mint': 'Mint a piece',
      '/collection': 'Your collection',
      '/system': 'The generative system',
      '/about': 'About the collection',
    }
    document.title = route.startsWith('/piece/')
      ? `IMDenza #${route.split('/')[2]} — On-chain artwork`
      : names[route]
        ? `${names[route]} — IMDenza`
        : 'IMDenza — The swarm, set in motion'
    document.querySelector<HTMLElement>('main')?.focus({ preventScroll: true })
  }, [route])
  const links = [
    ['/gallery', 'Explore'],
    ['/system', 'The system'],
    ['/about', 'About'],
    ['/collection', 'My collection'],
    ['/mint', 'Mint'],
  ]
  return (
    <>
      <a
        className="skip-link"
        href="#main"
        onClick={(e) => {
          e.preventDefault()
          document.getElementById('main')?.focus()
        }}
      >
        Skip to content
      </a>
      <header className="site-header">
        <a className="wordmark" href="#/" aria-label="IMDenza home">
          <svg
            aria-hidden="true"
            width="27"
            height="33"
            viewBox="0 0 27 33"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
          >
            <path d="M2 30C2 4 13 29 13 2M9 31C9 4 20 28 20 2M16 31C16 12 26 22 26 3" />
          </svg>
          IMDenza
        </a>
        <nav className="desktop-nav" aria-label="Main navigation">
          {links.map(([href, label]) => (
            <a
              key={href}
              href={`#${href}`}
              aria-current={route === href ? 'page' : undefined}
            >
              {label}
            </a>
          ))}
        </nav>
        <div className="header-controls">
          <WalletControl />
          <button
            className="icon-button menu-toggle"
            aria-label={menuOpen ? 'Close navigation' : 'Open navigation'}
            aria-expanded={menuOpen}
            aria-controls="mobile-nav"
            onClick={() => setMenuOpen((v) => !v)}
          >
            <svg
              aria-hidden="true"
              width="22"
              height="22"
              viewBox="0 0 24 24"
              stroke="currentColor"
              strokeWidth="1.5"
            >
              {menuOpen ? (
                <path d="m5 5 14 14M5 19 14-14" />
              ) : (
                <path d="M3 7h18M3 16h18" />
              )}
            </svg>
          </button>
        </div>
        {menuOpen && (
          <nav
            id="mobile-nav"
            className="mobile-nav"
            aria-label="Mobile navigation"
          >
            {links.map(([href, label]) => (
              <a
                key={href}
                href={`#${href}`}
                aria-current={route === href ? 'page' : undefined}
              >
                {label}
                <Arrow />
              </a>
            ))}
          </nav>
        )}
      </header>
      <main id="main" tabIndex={-1}>
        {route === '/' ? (
          <Home state={collection.data} />
        ) : route === '/gallery' ? (
          <Gallery state={collection.data} />
        ) : route === '/mint' ? (
          <Mint
            state={collection.data}
            verified={verification.data === true && !verification.isError}
          />
        ) : route === '/collection' ? (
          <Dashboard
            state={collection.data}
            verified={verification.data === true && !verification.isError}
          />
        ) : route === '/system' ? (
          <SystemPage state={collection.data} />
        ) : route === '/about' ? (
          <About />
        ) : route.startsWith('/piece/') ? (
          <PiecePage
            key={route}
            id={Number(route.split('/')[2])}
            state={collection.data}
          />
        ) : (
          <div className="page empty-state">
            <h1>Page not found.</h1>
            <a className="button" href="#/gallery">
              Explore the collection <Arrow />
            </a>
          </div>
        )}
        {(collection.isError || verification.isError) && (
          <div className="page connection-error">
            <ErrorNotice
              error={collection.error ?? verification.error}
              retry={() => {
                void collection.refetch()
                void verification.refetch()
              }}
            />
            <ConnectionSettings />
          </div>
        )}
        {tx.busy && route !== '/mint' && route !== '/collection' && (
          <div className="page">
            <Notice>
              {tx.status} <a href="#/mint">View transaction status</a>
            </Notice>
          </div>
        )}
      </main>
      <footer className="site-footer">
        <div className="footer-top">
          <a href="#/" className="wordmark">
            IMDenza
          </a>
          <p>Composed on-chain. Kept in motion.</p>
          <div className="footer-links">
            <External href={opensea()}>OpenSea</External>
            <External href={REPO}>GitHub</External>
            <External href={JOB}>Swarm job</External>
          </div>
        </div>
        <div className="footer-bottom">
          <span>3,333 works · Ethereum mainnet</span>
          <span>
            <i className="status-dot" />
            {collection.data
              ? `Read at block ${number(collection.data.block)}`
              : 'Connecting to Ethereum'}
          </span>
          <ConnectionSettings />
        </div>
      </footer>
    </>
  )
}

function Home({ state }: { state?: CollectionState }) {
  const [id, setId] = useState(1)
  const [live, setLive] = useState(false)
  const piece = usePiece(id)
  return (
    <div className="home">
      <section className="hero">
        <div className="hero-copy">
          <h1>
            The swarm,
            <br />
            <em>set in motion.</em>
          </h1>
          <p>
            3,333 animated flow fields,
            <br className="desktop-break" /> written on Ethereum.
          </p>
          <div className="hero-actions">
            <a className="button" href="#/gallery">
              Explore the collection <Arrow />
            </a>
            <a className="text-button" href="#/mint">
              Mint a piece <Arrow diagonal />
            </a>
          </div>
          <div className="hero-note">
            <span className="status-dot" />
            Fully on-chain. Always in motion.
          </div>
        </div>
        <div className="hero-work">
          <a href={`#/piece/${id}`} aria-label={`Explore IMDenza #${id}`}>
            <Art id={id} priority onLive={setLive} />
          </a>
          <div className="hero-caption">
            <div>
              <a href={`#/piece/${id}`}>
                IMDenza #{String(id).padStart(4, '0')} <Arrow diagonal />
              </a>
              <span>
                {piece.data
                  ? `${paletteNames[piece.data.traits.palette]} · ${scaleNames[piece.data.traits.scale]} scale`
                  : 'On-chain generative artwork'}
              </span>
            </div>
            <div className="hero-work-controls">
              <span className="live-label">
                {live ? 'Live from Ethereum' : 'On-chain snapshot'}
              </span>
              {state && state.minted > 1 ? (
                <div className="piece-nav">
                  <button
                    className="icon-button"
                    aria-label="Previous featured piece"
                    onClick={() =>
                      setId((n) => (n === 1 ? state.minted : n - 1))
                    }
                  >
                    ←
                  </button>
                  <button
                    className="icon-button"
                    aria-label="Next featured piece"
                    onClick={() =>
                      setId((n) => (n === state.minted ? 1 : n + 1))
                    }
                  >
                    →
                  </button>
                </div>
              ) : (
                <MotionButton />
              )}
            </div>
          </div>
        </div>
      </section>
      <section className="collection-facts" aria-label="Collection facts">
        <div>
          <strong>3,333</strong>
          <span>Unique compositions</span>
        </div>
        <div>
          <strong>0.069 IMD</strong>
          <span>Public mint price</span>
        </div>
        <div>
          <strong>6.9%</strong>
          <span>Royalties to holders</span>
        </div>
        <div>
          <strong>
            {state ? number(state.max - state.minted) : 'Reading…'}
          </strong>
          <span>Pieces remaining</span>
        </div>
      </section>
      <SystemIntro state={state} />
      <section className="home-mint">
        <div>
          <h2>Your own piece of the swarm.</h2>
          <p>
            Mint a new composition or check your eligibility for a free claim.
          </p>
        </div>
        <a className="button" href="#/mint">
          Find your piece <Arrow />
        </a>
      </section>
    </div>
  )
}
