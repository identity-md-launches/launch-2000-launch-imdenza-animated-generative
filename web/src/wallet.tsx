import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  useId,
  type ReactNode,
} from 'react'
import {
  useAccount,
  useConnect,
  useDisconnect,
  useSwitchChain,
  type Connector,
} from 'wagmi'
import { mainnet } from 'viem/chains'
import { getAddress } from 'viem'
import { Modal, External, ErrorNotice, Arrow } from './components'
import { customRpc, RPC_URLS } from './chain'
import { explorer, shortAddress } from './format'

const WalletContext = createContext({ open: () => {} })
export const useWalletSheet = () => useContext(WalletContext)
export function WalletProvider({
  children,
  hasWalletConnect,
}: {
  children: ReactNode
  hasWalletConnect: boolean
}) {
  const [open, setOpen] = useState(false)
  const [error, setError] = useState<unknown>()
  const [pending, setPending] = useState<string>()
  const [timedOut, setTimedOut] = useState(false)
  const { address, isConnected, connector: currentConnector } = useAccount()
  const { connectors, connectAsync, reset } = useConnect()
  const { disconnectAsync } = useDisconnect()
  const attempt = useRef(0)
  const mobile =
    /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) &&
    !connectors.some((c) => c.type === 'injected' && c.id !== 'injected') &&
    !(window as Window & { ethereum?: unknown }).ethereum
  const named = connectors.some(
    (c) => c.type === 'injected' && c.id !== 'injected',
  )
  const listed = [
    ...connectors.filter((c) => c.type === 'injected'),
    ...connectors.filter((c) => c.type !== 'injected'),
  ].filter(
    (c) =>
      !(c.id === 'injected' && named) && !(mobile && c.type === 'injected'),
  )
  useEffect(() => {
    if (isConnected && !pending) setOpen(false)
  }, [isConnected, pending])
  async function connect(connector: Connector) {
    if (pending) return
    const id = ++attempt.current
    setError(undefined)
    setPending(connector.uid)
    setTimedOut(false)
    const timer = setTimeout(() => {
      if (id === attempt.current) setTimedOut(true)
    }, 30_000)
    if (['walletConnect', 'coinbaseWalletSDK'].includes(connector.id))
      setOpen(false)
    try {
      await connectAsync({ connector })
      if (id === attempt.current) setOpen(false)
    } catch (e) {
      if (id === attempt.current) {
        setError(e)
        setOpen(true)
      }
    } finally {
      clearTimeout(timer)
      if (id === attempt.current) {
        setPending(undefined)
        setTimedOut(false)
      }
    }
  }
  function close() {
    setOpen(false)
  }
  const link = location.href
  const mobileLinks = [
    {
      name: 'MetaMask',
      id: 'metamask',
      href: `https://link.metamask.io/dapp/${link.replace(/^https?:\/\//, '')}`,
    },
    {
      name: 'Coinbase Wallet',
      id: 'coinbase',
      href: `https://go.cb-w.com/dapp?cb_url=${encodeURIComponent(link)}`,
    },
    {
      name: 'Rabby',
      id: 'rabby',
      href: `https://go.rabby.io/mobile/?_cmd=open-dapp&dapp=${encodeURIComponent(link)}`,
    },
    {
      name: 'Phantom',
      id: 'phantom',
      href: `https://phantom.app/ul/browse/${encodeURIComponent(link)}?ref=${encodeURIComponent(location.origin)}`,
    },
  ]
  return (
    <WalletContext.Provider
      value={{
        open: () => {
          setError(undefined)
          setOpen(true)
        },
      }}
    >
      {children}
      <Modal
        open={open}
        onClose={close}
        title={isConnected ? 'Your wallet' : 'Connect a wallet'}
      >
        {isConnected && address ? (
          <>
            <p className="break-word wallet-address">{getAddress(address)}</p>
            <External href={explorer('address', address)}>
              View on Etherscan
            </External>
            <button
              className="button secondary full-width"
              onClick={async () => {
                try {
                  await disconnectAsync({ connector: currentConnector })
                  setOpen(false)
                } catch (e) {
                  setError(e)
                }
              }}
            >
              Disconnect wallet
            </button>
          </>
        ) : (
          <>
            <p className="muted">
              Connect to mint a piece or view your collection.
            </p>
            <div className="wallet-list">
              {mobile &&
                mobileLinks.map((w) => (
                  <a className="wallet-row" href={w.href} key={w.id}>
                    <img
                      width="28"
                      height="28"
                      src={`./wallets/${w.id}.svg`}
                      alt=""
                    />
                    Open in {w.name}
                    <Arrow diagonal />
                  </a>
                ))}
              {listed.map((c) => (
                <button
                  key={c.uid}
                  className="wallet-row"
                  disabled={!!pending}
                  onClick={() => connect(c)}
                >
                  {c.icon ? (
                    <img width="28" height="28" src={c.icon} alt="" />
                  ) : (
                    <img
                      width="28"
                      height="28"
                      src={`./wallets/${c.id === 'coinbaseWalletSDK' ? 'coinbase' : c.id === 'walletConnect' ? 'walletconnect' : 'browser'}.svg`}
                      alt=""
                    />
                  )}
                  <span>
                    {c.id === 'injected'
                      ? 'Browser wallet'
                      : c.id === 'coinbaseWalletSDK'
                        ? mobile
                          ? 'Coinbase Smart Wallet'
                          : 'Coinbase Wallet'
                        : c.name}
                    {pending === c.uid ? ' · opening…' : ''}
                  </span>
                  <Arrow />
                </button>
              ))}
            </div>
            {timedOut && (
              <p role="status">
                Your wallet is still waiting. Open its prompt to continue or
                reject the request.{' '}
                <button
                  className="text-button"
                  onClick={() => location.reload()}
                >
                  Reset connection
                </button>
              </p>
            )}
            {!hasWalletConnect && (
              <p className="small muted">
                Browser wallets and Coinbase connect directly. WalletConnect
                relay is not configured for this site.
              </p>
            )}
            <p className="small muted">
              Connecting does not request a transaction or spend funds.
            </p>
          </>
        )}
        {!!error && (
          <>
            <ErrorNotice error={error} />
            <button
              className="text-button"
              onClick={() => {
                reset()
                setError(undefined)
                setPending(undefined)
              }}
            >
              Try connecting again
            </button>
          </>
        )}
      </Modal>
    </WalletContext.Provider>
  )
}
export function WalletControl() {
  const { address, isConnected, chainId } = useAccount()
  const { open } = useWalletSheet()
  const { switchChainAsync, isPending } = useSwitchChain()
  const [error, setError] = useState<unknown>()
  if (isConnected && chainId !== 1)
    return (
      <>
        <button
          className="button wallet-control"
          onClick={async () => {
            setError(undefined)
            try {
              await switchChainAsync({
                chainId: 1,
                addEthereumChainParameter: {
                  chainName: 'Ethereum',
                  nativeCurrency: mainnet.nativeCurrency,
                  rpcUrls: [...RPC_URLS],
                  blockExplorerUrls: ['https://etherscan.io'],
                },
              })
            } catch (e) {
              setError(e)
            }
          }}
          disabled={isPending}
        >
          {isPending ? 'Switching…' : 'Switch to Ethereum'}
        </button>
        {!!error && (
          <Modal
            open
            onClose={() => setError(undefined)}
            title="Switch network"
          >
            <ErrorNotice error={error} />
            <button
              className="button secondary"
              onClick={() => {
                setError(undefined)
                open()
              }}
            >
              Manage wallet
            </button>
          </Modal>
        )}
      </>
    )
  return (
    <button className="button wallet-control secondary" onClick={open}>
      <span className="wallet-dot" />
      {isConnected && address ? shortAddress(address) : 'Connect wallet'}
    </button>
  )
}
export function ConnectionSettings() {
  const rpcId = useId()
  const [open, setOpen] = useState(false)
  const [rpc, setRpc] = useState(customRpc ?? '')
  const [error, setError] = useState('')
  return (
    <>
      <button className="text-button" onClick={() => setOpen(true)}>
        Connection settings
      </button>
      <Modal
        open={open}
        onClose={() => setOpen(false)}
        title="Ethereum connection"
      >
        <p className="muted">
          On-chain artworks need an RPC that supports large contract reads. A
          custom endpoint is stored only in this browser.
        </p>
        <form
          onSubmit={(e) => {
            e.preventDefault()
            setError('')
            try {
              if (rpc && new URL(rpc).protocol !== 'https:') throw new Error()
              localStorage.setItem('imdenza.rpc', rpc.trim())
              location.reload()
            } catch {
              setError(
                'Enter a valid HTTPS RPC URL, or leave this blank to use the defaults.',
              )
            }
          }}
        >
          <label htmlFor={rpcId}>Custom Ethereum RPC (optional)</label>
          <input
            id={rpcId}
            type="url"
            value={rpc}
            onChange={(e) => setRpc(e.target.value)}
            placeholder="https://…"
            autoComplete="off"
            spellCheck={false}
            aria-describedby={`${rpcId}-help`}
          />
          <p id={`${rpcId}-help`} className="small muted">
            Default: PublicNode, with dRPC as fallback. Your RPC can see your
            read requests and public wallet address.
          </p>
          {error && (
            <p className="error-text" role="alert">
              {error}
            </p>
          )}
          <div className="button-row">
            <button className="button" type="submit">
              Save and reload
            </button>
            <button
              className="button secondary"
              type="button"
              onClick={() => {
                localStorage.removeItem('imdenza.rpc')
                location.reload()
              }}
            >
              Use defaults
            </button>
          </div>
        </form>
      </Modal>
    </>
  )
}
