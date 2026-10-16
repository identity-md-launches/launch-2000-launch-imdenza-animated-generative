import { COLLECTION, JOB, REPO, type CollectionState } from './chain'
import deployment from './generated/deployment.json'
import { Arrow, External } from './components'
import { explorer, number, opensea } from './format'

export function FlowDiagram() {
  return (
    <svg
      className="flow-diagram"
      viewBox="0 0 540 360"
      role="img"
      aria-label="Diagram of curved paths following a flow field, with space between strokes"
    >
      <g fill="none" stroke="currentColor" strokeWidth="1" opacity=".2">
        {Array.from({ length: 8 }, (_, y) =>
          Array.from({ length: 12 }, (_, x) => {
            const px = x * 43 + 30,
              py = y * 43 + 25
            const a = Math.sin(x / 3 + y / 4) * 45
            return (
              <path
                key={`${x}-${y}`}
                d={`M${px - 7} ${py}h14m-4-4 4 4-4 4`}
                transform={`rotate(${a} ${px} ${py})`}
              />
            )
          }),
        )}
      </g>
      <g fill="none" strokeLinecap="butt">
        <path
          stroke="#e4af8c"
          strokeWidth="15"
          d="M58 102C110 134 129 197 193 218S297 204 344 139 430 70 477 93"
        />
        <path
          stroke="#d4d0bf"
          strokeWidth="24"
          d="M44 146C107 179 133 253 209 262S321 224 366 172 441 117 483 129"
        />
        <path
          stroke="#819a86"
          strokeWidth="9"
          d="M78 63C138 103 158 176 204 178S265 163 305 110 391 21 455 44"
        />
        <path
          stroke="#b87d60"
          strokeWidth="31"
          d="M94 230C137 288 190 312 256 292S351 227 390 206"
        />
      </g>
    </svg>
  )
}
export function SystemIntro({ state }: { state?: CollectionState }) {
  return (
    <section className="system-intro">
      <div>
        <h2>History becomes a field.</h2>
        <p>
          Every recorded swarm job leaves a trace. A mint turns that shared
          history into a singular composition; new activity brings its motion to
          life.
        </p>
        <a className="text-button" href="#/system">
          Inside the generative system <Arrow />
        </a>
        <div className="system-live">
          <span>
            <i className="status-dot" />
            {state ? number(state.jobs) : 'Reading…'} recorded jobs
          </span>
          <span>
            {state ? `${(state.pulse / 10_000).toFixed(0)}%` : 'Reading…'} live
            pulse
          </span>
        </div>
      </div>
      <div className="diagram-wrap">
        <FlowDiagram />
        <p className="small muted">
          Flow-field schematic · artwork is rendered by the contracts
        </p>
      </div>
    </section>
  )
}
export function SystemPage({ state }: { state?: CollectionState }) {
  return (
    <div className="page editorial-page">
      <div className="page-heading">
        <h1>A field remembers.</h1>
        <p>One shared history. Thousands of individual expressions.</p>
      </div>
      <div className="editorial-lead">
        <p>
          IMDenza grows thick, curved strokes through a seeded flow field.
          Inspired by the generative language of Tyler Hobbs’ Fidenza, it adds a
          living source of variation: the history and activity of the IMD swarm.
        </p>
        <FlowDiagram />
      </div>
      <div className="system-stats">
        <div>
          <span>Jobs recorded on chain</span>
          <strong>{state ? number(state.jobs) : 'Reading…'}</strong>
        </div>
        <div>
          <span>Live activity pulse</span>
          <strong>
            {state ? `${(state.pulse / 10_000).toFixed(0)}%` : 'Reading…'}
          </strong>
        </div>
        <div>
          <span>Foundational job traces</span>
          <strong>First 16</strong>
        </div>
      </div>
      <div className="editorial-steps">
        <section>
          <span className="step-number">01</span>
          <div>
            <h2>The entire history, since block 0.</h2>
            <p>
              SwarmHistory is an append-only ledger designed to include the full
              IMD swarm job history, including backfilled jobs from the
              beginning. Each submitted record contains a unique job ID,
              category, agent count, outcome, and timestamp. Every record is
              folded into one rolling entropy hash.
            </p>
            <p>
              The ledger is permissionless: jobs must be recorded explicitly. It
              does not automatically discover the swarm’s history or verify that
              submissions are complete.{' '}
              {state
                ? `It currently contains ${number(state.jobs)} recorded ${state.jobs === 1 ? 'job' : 'jobs'}.`
                : 'The live count above reports the records currently available.'}{' '}
              {state?.jobs === 0
                ? 'No swarm jobs have been recorded yet, so existing pieces have no contributing job range.'
                : 'Each piece lists the exact range recorded when it was minted.'}
            </p>
            <External href={JOB}>Explore the collection’s swarm job</External>
          </div>
        </section>
        <section>
          <span className="step-number">02</span>
          <div>
            <h2>A moment, made permanent.</h2>
            <p>
              At mint, the collection combines the mint-context hash, the
              settled swarm entropy, and the unique token ID into a composition
              seed. It snapshots the job count and category profile from the
              preceding block.
            </p>
            <p>
              These values influence scale, turbulence, density, and palette
              probabilities. Recorded job categories add geometric accents. The
              first 16 foundational records leave faint structural traces in
              pieces minted after them.
            </p>
          </div>
        </section>
        <section>
          <span className="step-number">03</span>
          <div>
            <h2>Following an invisible current.</h2>
            <p>
              The field renderer grows each stroke step by step through a seeded
              noise field. A 96 × 96 collision grid leaves space between paths.
              Scale, turbulence, density, collision mode, and one of eight
              palette families give each field its character.
            </p>
            <p>
              The collection rejects reused mint hashes and composition seeds. A
              token’s identity is part of its seed; its composition and mint
              snapshot remain fixed.
            </p>
          </div>
        </section>
        <section>
          <span className="step-number">04</span>
          <div>
            <h2>Still composed. Always moving.</h2>
            <p>
              Newly recorded jobs add to a live activity pulse that decays with
              Ethereum blocks. The renderer reads this pulse when you load a
              piece: more activity increases the flow, breathing, saturation,
              and animation speed.
            </p>
            <p>
              The composition stays intact. CSS animation runs inside the SVG
              itself. You can pause it, download it, and regenerate it from the
              contracts without IPFS or a separate art server.
            </p>
          </div>
        </section>
      </div>
      <div className="editorial-end">
        <h2>See the system in motion.</h2>
        <a className="button" href="#/gallery">
          Explore the collection <Arrow />
        </a>
      </div>
    </div>
  )
}
export function About() {
  return (
    <div className="page editorial-page">
      <div className="page-heading">
        <h1>Art, held on Ethereum.</h1>
        <p>IMDenza is a collection of 3,333 animated generative works.</p>
      </div>
      <div className="about-intro">
        <p>
          Each piece is a flow field: an arrangement of curved strokes with its
          own rhythm, palette, and space. The image, traits, and animation are
          generated by Ethereum contracts. The swarm provides the history; your
          mint gives it a form.
        </p>
        <p>Built to be collected, revisited, and kept in motion.</p>
      </div>
      <dl className="spec-list">
        <div>
          <dt>Collection</dt>
          <dd>IMDenza · IMDENZA</dd>
        </div>
        <div>
          <dt>Maximum supply</dt>
          <dd>3,333 unique pieces</dd>
        </div>
        <div>
          <dt>Network & standard</dt>
          <dd>Ethereum mainnet · ERC721C</dd>
        </div>
        <div>
          <dt>Public mint</dt>
          <dd>0.069 IMD, plus Ethereum network fees</dd>
        </div>
        <div>
          <dt>Mint proceeds</dt>
          <dd>90% to the holder distributor · 10% to treasury</dd>
        </div>
        <div>
          <dt>Creator earnings</dt>
          <dd>6.9% royalties to the holder distributor</dd>
        </div>
        <div>
          <dt>Artwork & metadata</dt>
          <dd>On-chain animated SVG and embedded JSON</dd>
        </div>
        <div>
          <dt>Uniqueness</dt>
          <dd>
            Unique token IDs seed every composition; reused hashes and seeds are
            rejected
          </dd>
        </div>
        <div>
          <dt>Contract controls</dt>
          <dd>
            No pause, upgrades, or discretionary minting. One-time Identity MD
            collection configuration.
          </dd>
        </div>
      </dl>
      <div className="about-note">
        <h2>Value follows the artwork.</h2>
        <p>
          Mint proceeds and royalties are attributed pro rata to pieces that
          exist when the funds are distributed. A piece never shares earlier
          distributions. Unclaimed value follows the token and is paid to its
          current owner.
        </p>
        <p>
          ERC721C supports royalty enforcement through Limit Break’s transfer
          validator. Marketplace behavior and collection policy determine
          enforcement; the site does not certify a marketplace’s settings.
        </p>
        <a className="text-button" href="#/collection">
          Open holder dashboard <Arrow />
        </a>
      </div>
      <section className="contracts-section">
        <h2>Read the contracts.</h2>
        <p>
          Deployed on Ethereum mainnet. Every displayed artwork is read from
          this collection and its renderer.
        </p>
        <div className="contract-list">
          {deployment.contracts.map((c) => (
            <External key={c.name} href={explorer('address', c.address)}>
              <span>{c.name}</span>
              <code>{c.address}</code>
            </External>
          ))}
        </div>
        <div className="button-row">
          <External className="button secondary" href={REPO}>
            Source on GitHub
          </External>
          <External className="button secondary" href={JOB}>
            Swarm job
          </External>
          <External className="button secondary" href={opensea()}>
            OpenSea collection
          </External>
        </div>
        <p className="small muted">
          The holder distributor is created by IMDenza and resolved through{' '}
          <code>distributor()</code>. The dashboard reads its address directly
          from{' '}
          <a
            href={explorer('address', COLLECTION)}
            target="_blank"
            rel="noreferrer"
          >
            the collection contract
          </a>
          .
        </p>
      </section>
      <p className="small muted">
        IMDenza is inspired by Fidenza’s flow-field approach. It is an
        independent collection and is not affiliated with Tyler Hobbs or Art
        Blocks.
      </p>
    </div>
  )
}
