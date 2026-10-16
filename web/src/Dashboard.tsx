import { useState } from 'react'
import { useAccount } from 'wagmi'
import { useQuery } from '@tanstack/react-query'
import { type Address } from 'viem'
import {
  client,
  erc20Abi,
  IMD_A,
  IMD_B,
  nativeAsset,
  ownedPieces,
  type CollectionState,
} from './chain'
import { distributorAbi } from './generated/abis'
import {
  Arrow,
  ErrorNotice,
  External,
  Loading,
  Notice,
  PieceCard,
  TransactionStatus,
} from './components'
import { amount, explorer, fullAmount, number } from './format'
import { useWalletSheet } from './wallet'
import { useTransaction } from './transactions'

export function Dashboard({
  state,
  verified,
}: {
  state?: CollectionState
  verified: boolean
}) {
  const { address, chainId } = useAccount()
  const { open } = useWalletSheet()
  const tx = useTransaction()
  const [progress, setProgress] = useState(0)
  const [page, setPage] = useState(0)
  const owned = useQuery({
    queryKey: ['owned', address, state?.minted],
    enabled: !!address && !!state,
    queryFn: () => ownedPieces(address!, state!.minted, setProgress),
    staleTime: 30_000,
    retry: 1,
  })
  return (
    <div className="page">
      <div className="page-heading">
        <h1>Your collection.</h1>
        <p>Your artworks, and the value they share.</p>
      </div>
      {!address ? (
        <div className="empty-state dashboard-empty">
          <svg
            aria-hidden="true"
            width="64"
            height="64"
            viewBox="0 0 64 64"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.5"
          >
            <rect x="6" y="9" width="37" height="42" />
            <path d="M47 17h10v40H20v-2M15 40c7-30 13 15 20-20" />
          </svg>
          <h2>Art belongs here.</h2>
          <p>
            Connect your wallet to see your IMDenza pieces and claim your share
            of mint proceeds and royalties.
          </p>
          <button className="button" onClick={open}>
            Connect wallet <Arrow />
          </button>
          {tx.busy && <TransactionStatus {...tx} />}
        </div>
      ) : (
        <>
          <div className="dashboard-summary">
            <div>
              <span>Pieces in your wallet</span>
              <strong>
                {owned.data ? number(owned.data.length) : 'Reading…'}
              </strong>
            </div>
            <div>
              <span>Share of current supply</span>
              <strong>
                {owned.data && state
                  ? `${state.minted ? ((owned.data.length / state.minted) * 100).toLocaleString('en-US', { maximumFractionDigits: 2 }) : 0}%`
                  : 'Reading…'}
              </strong>
            </div>
            <div>
              <span>Mint proceeds to holders</span>
              <strong>90%</strong>
            </div>
          </div>
          {owned.isPending && (
            <Loading>
              Finding your pieces
              {state && state.minted > 60
                ? ` · ${progress} / ${state.minted} checked`
                : ''}
              …
            </Loading>
          )}
          {owned.isError && (
            <ErrorNotice error={owned.error} retry={() => owned.refetch()} />
          )}
          {owned.data && state && (
            <>
              <Payouts
                key={address}
                state={state}
                ids={owned.data}
                verified={verified && chainId === 1}
              />
              <section className="collection-section">
                <div className="section-heading">
                  <h2>Your pieces</h2>
                  <button
                    className="text-button"
                    disabled={owned.isFetching}
                    onClick={() => owned.refetch()}
                  >
                    {owned.isFetching ? 'Refreshing…' : 'Refresh ownership'}
                  </button>
                </div>
                {owned.data.length ? (
                  <>
                    <div className="gallery-grid">
                      {owned.data
                        .slice(page * 12, (page + 1) * 12)
                        .map((id) => (
                          <PieceCard key={id} id={id} />
                        ))}
                    </div>
                    {owned.data.length > 12 && (
                      <div className="pagination">
                        <button
                          className="button secondary"
                          disabled={page === 0}
                          onClick={() => setPage((p) => p - 1)}
                        >
                          Previous
                        </button>
                        <span>
                          Page {page + 1} of {Math.ceil(owned.data.length / 12)}
                        </span>
                        <button
                          className="button secondary"
                          disabled={(page + 1) * 12 >= owned.data.length}
                          onClick={() => setPage((p) => p + 1)}
                        >
                          Next
                        </button>
                      </div>
                    )}
                  </>
                ) : (
                  <div className="empty-state">
                    <h3>No IMDenza pieces in this wallet yet.</h3>
                    <p>
                      Mint a composition or explore the collection to find your
                      first piece.
                    </p>
                    <a className="button" href="#/mint">
                      Mint a piece <Arrow />
                    </a>
                  </div>
                )}
              </section>
            </>
          )}
        </>
      )}
    </div>
  )
}

function Payouts({
  state,
  ids,
  verified,
}: {
  state: CollectionState
  ids: number[]
  verified: boolean
}) {
  const tx = useTransaction()
  const { address } = useAccount()
  const assets = [
    { address: IMD_A, label: 'IMD · token A', symbol: 'IMD' },
    { address: nativeAsset, label: 'ETH · royalties', symbol: 'ETH' },
    { address: state.weth, label: 'WETH · royalties', symbol: 'WETH' },
    { address: IMD_B, label: 'IMD · token B', symbol: 'IMD' },
  ]
  const [selected, setSelected] = useState(0)
  const asset = assets[selected]
  const pending = useQuery({
    queryKey: ['payouts', state.distributor, asset.address, ids, address],
    queryFn: async () => {
      const block = await client.getBlockNumber()
      const code =
        asset.address === nativeAsset
          ? undefined
          : await client.getCode({
              address: asset.address as Address,
              blockNumber: block,
            })
      if (asset.address !== nativeAsset && (!code || code === '0x'))
        return {
          available: false,
          pending: [] as { id: number; amount: bigint }[],
          total: 0n,
          unallocated: 0n,
          decimals: 18,
        }
      const [reserved, balance, decimals] = await Promise.all([
        client.readContract({
          address: state.distributor,
          abi: distributorAbi,
          functionName: 'reserved',
          args: [asset.address as Address],
          blockNumber: block,
        }),
        asset.address === nativeAsset
          ? client.getBalance({
              address: state.distributor,
              blockNumber: block,
            })
          : client.readContract({
              address: asset.address as Address,
              abi: erc20Abi,
              functionName: 'balanceOf',
              args: [state.distributor],
              blockNumber: block,
            }),
        asset.address === nativeAsset
          ? 18
          : client
              .readContract({
                address: asset.address as Address,
                abi: erc20Abi,
                functionName: 'decimals',
                blockNumber: block,
              })
              .catch(() => 18),
      ])
      const amounts: { id: number; amount: bigint }[] = []
      for (let start = 0; start < ids.length; start += 60) {
        const batch = ids.slice(start, start + 60)
        const values = await Promise.all(
          batch.map((id) =>
            client.readContract({
              address: state.distributor,
              abi: distributorAbi,
              functionName: 'pending',
              args: [asset.address as Address, BigInt(id)],
              blockNumber: block,
            }),
          ),
        )
        amounts.push(...batch.map((id, i) => ({ id, amount: values[i] })))
      }
      return {
        available: true,
        pending: amounts,
        total: amounts.reduce((sum, item) => sum + item.amount, 0n),
        unallocated: balance > reserved ? balance - reserved : 0n,
        decimals,
      }
    },
    staleTime: 15_000,
    retry: 1,
  })
  const data = pending.data
  const claimable =
    data?.pending.filter((p) => p.amount > 0n).slice(0, 80) ?? []
  const thisClaim = claimable.reduce((sum, p) => sum + p.amount, 0n)
  return (
    <section className="payout-section">
      <div className="payout-intro">
        <h2>A share in every piece.</h2>
        <p>
          90% of mint proceeds and 6.9% sale royalties flow to the holder
          distributor. Each piece shares equally in distributions made after it
          was minted.
        </p>
        <p className="small muted">
          Unclaimed value travels with the artwork. Payouts go to its current
          owner. The current supply share above is not a promise of future
          income.
        </p>
        <External href={explorer('address', state.distributor)}>
          View holder distributor
        </External>
      </div>
      <div className="payout-panel">
        <label htmlFor="payout-asset">Asset to claim</label>
        <select
          id="payout-asset"
          value={selected}
          onChange={(e) => setSelected(Number(e.target.value))}
          disabled={tx.busy}
        >
          {assets.map((a, i) => (
            <option key={a.address} value={i}>
              {a.label}
            </option>
          ))}
        </select>
        {pending.isPending && <Loading>Reading distribution balances…</Loading>}
        {pending.isError && (
          <ErrorNotice error={pending.error} retry={() => pending.refetch()} />
        )}
        {data &&
          (!data.available ? (
            <Notice>This asset is not deployed on Ethereum.</Notice>
          ) : (
            <>
              <div className="payout-total">
                <span>Available to your pieces</span>
                <strong title={fullAmount(data.total, data.decimals)}>
                  {amount(data.total, data.decimals)}{' '}
                  <span>{asset.symbol}</span>
                </strong>
              </div>
              <p className="small muted break-word">
                Exact balance: {fullAmount(data.total, data.decimals)}{' '}
                {asset.symbol}
              </p>
              <button
                className="button full-width"
                disabled={!verified || tx.busy || !claimable.length}
                onClick={() =>
                  tx.run({
                    address: state.distributor,
                    abi: distributorAbi,
                    functionName: 'claim',
                    args: [asset.address, claimable.map((p) => BigInt(p.id))],
                    label: `${asset.symbol} payout`,
                  })
                }
              >
                {tx.busy
                  ? 'Transaction in progress…'
                  : claimable.length
                    ? `Claim ${amount(thisClaim, data.decimals)} ${asset.symbol}`
                    : 'Nothing to claim yet'}
                <Arrow />
              </button>
              <p className="small muted">
                {claimable.length > 0
                  ? `Claims ${claimable.length} piece${claimable.length === 1 ? '' : 's'} in this transaction, up to 80 at a time. Network fees apply.`
                  : 'New proceeds appear here after distribution.'}
              </p>
              <div className="distribution-row">
                <div>
                  <span>Awaiting distribution to all holders</span>
                  <strong title={fullAmount(data.unallocated, data.decimals)}>
                    {amount(data.unallocated, data.decimals)} {asset.symbol}
                  </strong>
                </div>
                <button
                  className="button secondary"
                  disabled={
                    !verified || tx.busy || !state.minted || !data.unallocated
                  }
                  onClick={() =>
                    tx.run({
                      address: state.distributor,
                      abi: distributorAbi,
                      functionName: 'distribute',
                      args: [asset.address],
                      label: `${asset.symbol} distribution`,
                    })
                  }
                >
                  Distribute
                </button>
              </div>
              <p className="small muted">
                Distribution allocates received funds across eligible pieces.
                Claiming then transfers your share to your wallet. These are
                separate transactions.
              </p>
            </>
          ))}
        {!verified && (
          <p className="small muted">
            Transactions require Ethereum mainnet and verified contract code.
          </p>
        )}
        <TransactionStatus {...tx} />
      </div>
    </section>
  )
}
