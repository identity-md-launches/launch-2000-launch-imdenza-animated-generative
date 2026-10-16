import React from 'react'
import { createRoot } from 'react-dom/client'
import { WagmiProvider } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import '@fontsource/dm-sans/latin-400.css'
import '@fontsource/dm-sans/latin-500.css'
import '@fontsource/instrument-serif/latin-400.css'
import '@fontsource/instrument-serif/latin-400-italic.css'
import './styles.css'
import { App } from './App'
import { makeWalletConfig } from './chain'
import { WalletProvider } from './wallet'
import { MotionProvider } from './components'
import { TransactionProvider } from './transactions'

const queries = new QueryClient({
  defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: false } },
})
class ErrorBoundary extends React.Component<
  { children: React.ReactNode },
  { failed: boolean }
> {
  state = { failed: false }
  static getDerivedStateFromError() {
    return { failed: true }
  }
  render() {
    return this.state.failed ? (
      <main className="page empty-state">
        <h1>IMDenza</h1>
        <p>The gallery could not start. Reload to reconnect to Ethereum.</p>
        <button className="button" onClick={() => location.reload()}>
          Reload gallery
        </button>
      </main>
    ) : (
      this.props.children
    )
  }
}
async function start() {
  let projectId = ''
  try {
    const response = await fetch('./site-config.json', {
      signal: AbortSignal.timeout(2500),
    })
    const config = await response.json()
    if (
      typeof config.walletConnectProjectId === 'string' &&
      /^[a-f0-9]{32}$/i.test(config.walletConnectProjectId)
    )
      projectId = config.walletConnectProjectId
  } catch {
    /* Direct wallets work without a relay configuration. */
  }
  const config = makeWalletConfig(projectId)
  createRoot(document.getElementById('root')!).render(
    <ErrorBoundary>
      <WagmiProvider config={config}>
        <QueryClientProvider client={queries}>
          <WalletProvider hasWalletConnect={!!projectId}>
            <MotionProvider>
              <TransactionProvider>
                <App />
              </TransactionProvider>
            </MotionProvider>
          </WalletProvider>
        </QueryClientProvider>
      </WagmiProvider>
    </ErrorBoundary>,
  )
}
void start()
