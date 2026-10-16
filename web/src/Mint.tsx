import { useEffect, useState } from 'react'
import { useAccount } from 'wagmi'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { zeroAddress, type Address } from 'viem'
import {
  ART_BLOCKS,
  COLLECTION,
  IDENTITY,
  IMD_A,
  IMD_B,
  client,
  erc20Abi,
  erc721Abi,
  readCollection,
  type CollectionState,
} from './chain'
import { collectionAbi } from './generated/abis'
import {
  Arrow,
  Art,
  ErrorNotice,
  External,
  Loading,
  Notice,
  TransactionStatus,
} from './components'
import { amount, explorer, fullAmount, number, sameAddress } from './format'
import { useWalletSheet } from './wallet'
import { useTransaction } from './transactions'

type Props = { state?: CollectionState; verified: boolean }
export function Mint({ state, verified }: Props) {
  const queries = useQueryClient()
  const { address, isConnected, chainId } = useAccount()
  const { open } = useWalletSheet()
  const tx = useTransaction()
  const [token, setToken] = useState<Address>(IMD_A)
  const [tab, setTab] = useState<'public' | 'free'>('public')
  const soldOut = !!state && state.minted >= state.max
  const balances = useQuery({
    queryKey: ['mint-balance', address, token],
    enabled: !!address,
    queryFn: async () => {
      const code = await client.getCode({ address: token })
      if (!code || code === '0x')
        return {
          available: false,
          balance: 0n,
          allowance: 0n,
          price: 0n,
          decimals: 18,
        }
      const [balance, allowance, price, decimals] = await Promise.all([
        client.readContract({
          address: token,
          abi: erc20Abi,
          functionName: 'balanceOf',
          args: [address!],
        }),
        client.readContract({
          address: token,
          abi: erc20Abi,
          functionName: 'allowance',
          args: [address!, COLLECTION],
        }),
        client.readContract({
          ...readCollection,
          functionName: 'mintPrice',
          args: [token],
        }),
        client
          .readContract({
            address: token,
            abi: erc20Abi,
            functionName: 'decimals',
          })
          .catch(() => 18),
      ])
      return { available: true, balance, allowance, price, decimals }
    },
    staleTime: 15_000,
    retry: 1,
  })
  const flags = useQuery({
    queryKey: ['claim-flags', address],
    queryFn: () =>
      client.readContract({
        ...readCollection,
        functionName: 'claimFlags',
        args: [address!],
      }),
    enabled: !!address,
    staleTime: 15_000,
  })
  const balance = balances.data
  const approved = !!balance && balance.allowance >= balance.price
  const canTransact =
    verified && !!state && !soldOut && chainId === 1 && !tx.busy
  return (
    <div className="page mint-page">
      <div className="page-heading">
        <h1>Mint a living artwork.</h1>
        <p>One mint. One composition. Entirely on Ethereum.</p>
      </div>
      <div className="mint-layout">
        <div className="mint-art">
          <Art id={1} priority />
          <div className="art-foot">
            <span>IMDenza #0001</span>
            <span>Your piece is revealed at mint</span>
          </div>
          <p className="muted small">
            The artwork shown is an existing piece. Every mint creates its own
            composition.
          </p>
        </div>
        <div className="mint-controls">
          <div className="supply-head">
            <span>Available to mint</span>
            <strong>
              {state
                ? `${number(state.max - state.minted)} / ${number(state.max)}`
                : 'Reading supply…'}
            </strong>
          </div>
          <div
            className="supply-track"
            role="meter"
            aria-label="Pieces minted"
            aria-valuemin={0}
            aria-valuemax={state?.max ?? 3333}
            aria-valuenow={state?.minted ?? 0}
          >
            <span
              style={{
                width: `${state ? (state.minted / state.max) * 100 : 0}%`,
              }}
            />
          </div>
          <div className="segmented" aria-label="Mint route">
            <button
              aria-pressed={tab === 'public'}
              onClick={() => setTab('public')}
            >
              Public mint
            </button>
            <button
              aria-pressed={tab === 'free'}
              onClick={() => setTab('free')}
            >
              Free claims
            </button>
          </div>
          {soldOut && (
            <Notice>
              All 3,333 pieces have been minted.{' '}
              <a href="#/gallery">Explore the collection</a>.
            </Notice>
          )}
          {tab === 'public' ? (
            <div className="mint-panel">
              <h2>Make a piece your own.</h2>
              <p className="mint-price">
                0.069 <span>IMD</span>
              </p>
              <p className="muted">
                90% of mint proceeds go to holders. 10% goes to the treasury.
                Ethereum network fees are paid separately in ETH.
              </p>
              <label htmlFor="payment-token">Pay with</label>
              <select
                id="payment-token"
                value={token}
                onChange={(e) => {
                  setToken(e.target.value as Address)
                  tx.clear()
                }}
                disabled={tx.busy}
              >
                <option value={IMD_A}>IMD · 0xd34a…63b7</option>
                <option value={IMD_B}>IMD · 0x5f7b…7127</option>
              </select>
              <External className="small" href={explorer('address', token)}>
                Verify payment token
              </External>
              {isConnected && balances.isPending && (
                <Loading>Checking balance and allowance…</Loading>
              )}
              {balances.isError && (
                <ErrorNotice
                  error={balances.error}
                  retry={() => balances.refetch()}
                />
              )}
              {balance && (
                <div className="balance-line">
                  <span>Wallet balance</span>
                  <span title={fullAmount(balance.balance, balance.decimals)}>
                    {amount(balance.balance, balance.decimals)} IMD
                  </span>
                </div>
              )}
              {balance && !balance.available && (
                <Notice>
                  This IMD token has no deployed code. Choose the other payment
                  token.
                </Notice>
              )}
              {balance?.available && balance.balance < balance.price && (
                <Notice>
                  You need at least 0.069 IMD in this wallet to mint.
                </Notice>
              )}
              {!isConnected ? (
                <button className="button full-width" onClick={open}>
                  Connect to mint <Arrow />
                </button>
              ) : (
                <>
                  <div className="mint-steps">
                    <span className={approved ? 'complete' : ''}>
                      1. Approve 0.069 IMD
                    </span>
                    <span>2. Mint your piece</span>
                  </div>
                  <button
                    className="button full-width"
                    disabled={
                      !canTransact ||
                      !balance?.available ||
                      balance.balance < balance.price
                    }
                    onClick={() =>
                      approved
                        ? tx.run({
                            address: COLLECTION,
                            abi: collectionAbi,
                            functionName: 'mint',
                            args: [token],
                            label: 'Mint',
                          })
                        : tx.run({
                            address: token,
                            abi: erc20Abi,
                            functionName: 'approve',
                            args: [COLLECTION, balance!.price],
                            label: 'IMD approval',
                          })
                    }
                  >
                    {tx.busy
                      ? 'Transaction in progress…'
                      : soldOut
                        ? 'Collection sold out'
                        : approved
                          ? 'Mint for 0.069 IMD'
                          : 'Approve 0.069 IMD'}
                    <Arrow />
                  </button>
                  <p className="small muted">
                    {approved
                      ? 'Your allowance is ready. Minting requests one transaction.'
                      : 'Approval allows this collection to spend exactly the mint price. Minting is a separate transaction.'}
                  </p>
                </>
              )}
            </div>
          ) : (
            <div className="claim-panel">
              <h2>A piece for the community.</h2>
              <p className="muted">
                Each qualifying route grants one free claim per wallet. Identity
                MD and Fidenza NFTs can each be used only once. Network fees
                still apply.
              </p>
              {!address ? (
                <>
                  <ul className="eligibility-list">
                    <li>Hold an Identity MD NFT</li>
                    <li>Hold more than 25 IMD in either supported token</li>
                    <li>Hold a Fidenza (Art Blocks project 78)</li>
                  </ul>
                  <button className="button full-width" onClick={open}>
                    Check my eligibility <Arrow />
                  </button>
                </>
              ) : (
                <>
                  {flags.isError ? (
                    <ErrorNotice
                      error={flags.error}
                      retry={() => flags.refetch()}
                    />
                  ) : flags.data === undefined ? (
                    <Loading>Checking claim history…</Loading>
                  ) : (
                    <>
                      <ImdClaim
                        address={address}
                        used={!!(flags.data & 2)}
                        enabled={canTransact}
                      />
                      <NftClaim
                        kind="identity"
                        address={address}
                        used={!!(flags.data & 1)}
                        enabled={canTransact}
                        configured={state?.identity}
                      />
                      <NftClaim
                        kind="fidenza"
                        address={address}
                        used={!!(flags.data & 4)}
                        enabled={canTransact}
                      />
                    </>
                  )}
                </>
              )}
            </div>
          )}
          {isConnected && (
            <button
              className="text-button"
              disabled={tx.busy}
              onClick={() =>
                queries.invalidateQueries({
                  predicate: (query) =>
                    [
                      'mint-balance',
                      'claim-flags',
                      'imd-eligibility',
                      'nft-eligibility',
                    ].includes(String(query.queryKey[0])),
                })
              }
            >
              Refresh eligibility & balance
            </button>
          )}
          {isConnected && chainId !== 1 && (
            <Notice>
              Switch to Ethereum using the wallet control above to continue.
            </Notice>
          )}
          {isConnected && !verified && (
            <Notice>
              Verifying the deployed contracts before enabling transactions…
            </Notice>
          )}
          <TransactionStatus {...tx} />
          {tx.mintedId && (
            <a
              className="button secondary full-width"
              href={`#/piece/${tx.mintedId}`}
            >
              View your new piece <Arrow />
            </a>
          )}
        </div>
      </div>
    </div>
  )
}
function ImdClaim({
  address,
  used,
  enabled,
}: {
  address: Address
  used: boolean
  enabled: boolean
}) {
  const tx = useTransaction()
  const eligibility = useQuery({
    queryKey: ['imd-eligibility', address],
    queryFn: () =>
      client.readContract({
        ...readCollection,
        functionName: 'holdsImd',
        args: [address],
      }),
    staleTime: 15_000,
  })
  return (
    <div className="claim-route">
      <div className="row-between">
        <h3>IMD holder</h3>
        <span className="small">
          {used
            ? 'Already claimed'
            : eligibility.isError
              ? 'Check unavailable'
              : eligibility.data
                ? 'Eligible'
                : eligibility.isPending
                  ? 'Checking…'
                  : 'Not eligible'}
        </span>
      </div>
      <p className="small muted">
        Strictly more than 25 IMD in either token. Balances are checked
        independently.
      </p>
      {eligibility.isError && (
        <ErrorNotice
          error={eligibility.error}
          retry={() => eligibility.refetch()}
        />
      )}
      <button
        className="button secondary full-width"
        disabled={!enabled || used || !eligibility.data || eligibility.isError}
        onClick={() =>
          tx.run({
            address: COLLECTION,
            abi: collectionAbi,
            functionName: 'claimWithImd',
            label: 'Free IMD-holder claim',
          })
        }
      >
        Claim with IMD holdings <Arrow />
      </button>
    </div>
  )
}
async function findNft(
  address: Address,
  collection: Address,
  fidenza: boolean,
) {
  const count = await client.readContract({
    address: collection,
    abi: erc721Abi,
    functionName: 'balanceOf',
    args: [address],
  })
  if (count === 0n) return { tokenId: undefined, count, manual: false }
  let ids: readonly bigint[]
  try {
    ids = (
      await client.readContract({
        address: collection,
        abi: erc721Abi,
        functionName: 'tokensOfOwner',
        args: [address],
      })
    ).slice(0, 200)
  } catch {
    try {
      ids = await Promise.all(
        Array.from({ length: Math.min(Number(count), 200) }, (_, i) =>
          client.readContract({
            address: collection,
            abi: erc721Abi,
            functionName: 'tokenOfOwnerByIndex',
            args: [address, BigInt(i)],
          }),
        ),
      )
    } catch {
      return { tokenId: undefined, count, manual: true }
    }
  }
  const candidates = ids.filter((id) => !fidenza || id / 1_000_000n === 78n)
  const used = await Promise.all(
    candidates.map((id) =>
      client.readContract({
        ...readCollection,
        functionName: fidenza ? 'fidenzaTokenUsed' : 'identityTokenUsed',
        args: [id],
      }),
    ),
  )
  return {
    tokenId: candidates.find((_, i) => !used[i]),
    count,
    manual: Number(count) > 200,
  }
}
function NftClaim({
  kind,
  address,
  used,
  enabled,
  configured,
}: {
  kind: 'identity' | 'fidenza'
  address: Address
  used: boolean
  enabled: boolean
  configured?: Address
}) {
  const fidenza = kind === 'fidenza'
  const collection = fidenza ? ART_BLOCKS : IDENTITY
  const ready =
    fidenza ||
    (!!configured &&
      configured !== zeroAddress &&
      sameAddress(configured, IDENTITY))
  const tx = useTransaction()
  const [input, setInput] = useState('')
  const [checked, setChecked] = useState<bigint>()
  const [error, setError] = useState<unknown>()
  const [checking, setChecking] = useState(false)
  const query = useQuery({
    queryKey: ['nft-eligibility', address, kind, configured],
    enabled: ready && !used,
    queryFn: () => findNft(address, collection, fidenza),
    staleTime: 30_000,
    retry: 1,
  })
  useEffect(() => {
    setChecked(undefined)
    setInput('')
    setError(undefined)
  }, [address])
  const tokenId = input.trim() ? checked : query.data?.tokenId
  async function check() {
    setError(undefined)
    setChecked(undefined)
    setChecking(true)
    try {
      if (!/^\d+$/.test(input))
        throw new Error('Enter a whole-number token ID.')
      const id = BigInt(input)
      if (fidenza && id / 1_000_000n !== 78n)
        throw new Error(
          'Fidenza token IDs are 78000000–78999999. Enter the full Art Blocks token ID.',
        )
      const [owner, wasUsed] = await Promise.all([
        client.readContract({
          address: collection,
          abi: erc721Abi,
          functionName: 'ownerOf',
          args: [id],
        }),
        client.readContract({
          ...readCollection,
          functionName: fidenza ? 'fidenzaTokenUsed' : 'identityTokenUsed',
          args: [id],
        }),
      ])
      if (!sameAddress(owner, address))
        throw new Error(
          'This NFT is not owned by your connected wallet. Check the token ID.',
        )
      if (wasUsed)
        throw new Error(
          'This NFT has already been used for a free claim. Check another token.',
        )
      setChecked(id)
    } catch (e) {
      setError(e)
    } finally {
      setChecking(false)
    }
  }
  return (
    <div className="claim-route">
      <div className="row-between">
        <h3>{fidenza ? 'Fidenza holder' : 'Identity MD holder'}</h3>
        <span className="small">
          {used
            ? 'Already claimed'
            : !ready
              ? 'Unavailable'
              : tokenId !== undefined
                ? 'Eligible'
                : query.isPending
                  ? 'Checking…'
                  : 'No eligible NFT found'}
        </span>
      </div>
      {!ready ? (
        <p className="small muted">
          The collection’s Identity MD setting has not been verified against the
          official address. This route is unavailable.
        </p>
      ) : (
        <>
          {tokenId !== undefined && (
            <p className="small">Verified NFT #{tokenId.toString()}</p>
          )}
          {query.isError && (
            <ErrorNotice error={query.error} retry={() => query.refetch()} />
          )}
          {query.data?.manual && (
            <p className="small muted">
              Automatic discovery is limited for this collection. Verify a token
              ID below.
            </p>
          )}
          {!used && (
            <details>
              <summary>Check a specific token ID</summary>
              <form
                className="token-check"
                onSubmit={(e) => {
                  e.preventDefault()
                  void check()
                }}
              >
                <label htmlFor={`${kind}-id`}>
                  {fidenza
                    ? 'Full Art Blocks token ID'
                    : 'Identity MD token ID'}
                </label>
                <div className="input-action">
                  <input
                    id={`${kind}-id`}
                    value={input}
                    inputMode="numeric"
                    pattern="[0-9]+"
                    required
                    aria-invalid={!!error}
                    aria-describedby={error ? `${kind}-error` : undefined}
                    onChange={(e) => {
                      setInput(e.target.value)
                      setChecked(undefined)
                      setError(undefined)
                    }}
                  />
                  <button
                    className="button secondary"
                    disabled={checking}
                    type="submit"
                  >
                    {checking ? 'Checking…' : 'Verify'}
                  </button>
                </div>
              </form>
              {!!error && (
                <div id={`${kind}-error`}>
                  <ErrorNotice error={error} />
                </div>
              )}
            </details>
          )}
          <button
            className="button secondary full-width"
            disabled={!enabled || used || tokenId === undefined}
            onClick={() =>
              tx.run({
                address: COLLECTION,
                abi: collectionAbi,
                functionName: fidenza
                  ? 'claimWithFidenza'
                  : 'claimWithIdentityMd',
                args: [tokenId!],
                label: fidenza
                  ? 'Free Fidenza-holder claim'
                  : 'Free Identity MD claim',
              })
            }
          >
            Claim with {fidenza ? 'Fidenza' : 'Identity MD'} <Arrow />
          </button>
        </>
      )}
    </div>
  )
}
