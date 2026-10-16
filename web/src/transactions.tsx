import { createContext, useContext, useState, type ReactNode } from 'react'
import { useAccount, useWalletClient } from 'wagmi'
import { useQueryClient } from '@tanstack/react-query'
import {
  decodeEventLog,
  type Abi,
  type Address,
  type Hash,
  type TransactionReceipt,
} from 'viem'
import { mainnet } from 'viem/chains'
import { client, COLLECTION, verifyDeployment } from './chain'
import { sameAddress } from './format'
import { collectionAbi } from './generated/abis'

type Transaction = {
  address: Address
  abi: Abi
  functionName: string
  args?: readonly unknown[]
  label: string
}
type State = {
  busy: boolean
  status: string
  hash?: Hash
  error?: unknown
  mintedId?: number
  uncertain?: boolean
  label?: string
}
type Context = State & {
  run: (tx: Transaction) => Promise<boolean>
  clear: () => void
  check: () => Promise<void>
  resetPending: () => void
}
const TransactionContext = createContext<Context>({
  busy: false,
  status: '',
  run: async () => false,
  clear: () => {},
  check: async () => {},
  resetPending: () => {},
})
export const useTransaction = () => useContext(TransactionContext)
function remember(hash?: Hash, label?: string) {
  try {
    if (hash)
      sessionStorage.setItem('imdenza.pending', JSON.stringify({ hash, label }))
    else sessionStorage.removeItem('imdenza.pending')
  } catch {
    /* The in-memory transaction remains available. */
  }
}
function restored(): State {
  try {
    const pending = JSON.parse(
      sessionStorage.getItem('imdenza.pending') ?? 'null',
    )
    if (pending && /^0x[0-9a-f]{64}$/i.test(pending.hash))
      return {
        busy: true,
        uncertain: true,
        hash: pending.hash,
        label: pending.label,
        status:
          'A submitted transaction needs a status check before sending another.',
      }
  } catch {
    /* No stored transaction. */
  }
  return { busy: false, status: '' }
}
export function TransactionProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<State>(restored)
  const { address, chainId } = useAccount()
  const { data: wallet } = useWalletClient()
  const queries = useQueryClient()
  async function finish(
    receipt: TransactionReceipt,
    label: string,
    cancelled = false,
  ) {
    remember()
    if (cancelled || receipt.status !== 'success') {
      setState({
        busy: false,
        hash: receipt.transactionHash,
        status: cancelled
          ? 'Transaction cancelled. No action was completed.'
          : 'Transaction reverted. Refresh your balances before trying again.',
      })
      await queries.invalidateQueries()
      return false
    }
    let mintedId: number | undefined
    for (const log of receipt.logs) {
      if (!sameAddress(log.address, COLLECTION)) continue
      try {
        const decoded = decodeEventLog({
          abi: collectionAbi,
          data: log.data,
          topics: log.topics,
          eventName: 'Minted',
        })
        mintedId = Number(decoded.args.tokenId)
      } catch {
        /* Other events are expected. */
      }
    }
    setState({
      busy: false,
      status: `${label} confirmed.${mintedId ? ` IMDenza #${mintedId} is now in your wallet.` : ''}`,
      hash: receipt.transactionHash,
      mintedId,
    })
    await queries.invalidateQueries()
    return true
  }
  async function check() {
    if (!state.hash) return
    setState((previous) => ({
      ...previous,
      busy: true,
      uncertain: false,
      error: undefined,
      status: 'Checking the submitted transaction…',
    }))
    try {
      const receipt = await client.getTransactionReceipt({ hash: state.hash })
      await finish(receipt, state.label ?? 'Transaction')
    } catch {
      setState((previous) => ({
        ...previous,
        busy: true,
        uncertain: true,
        status:
          'This transaction is not confirmed here yet. Check Etherscan, then check again. New transactions stay disabled to prevent duplicate submissions.',
      }))
    }
  }
  async function run(tx: Transaction) {
    if (state.busy) return false
    setState({
      busy: true,
      label: tx.label,
      status: `Checking ${tx.label.toLowerCase()}…`,
    })
    let submitted: Hash | undefined
    try {
      if (!wallet || !address)
        throw new Error('Connect your wallet to continue.')
      if (chainId !== 1 || (await wallet.getChainId()) !== 1)
        throw new Error('Switch your wallet to Ethereum mainnet to continue.')
      await verifyDeployment()
      const { request } = await client.simulateContract({
        address: tx.address,
        abi: tx.abi,
        functionName: tx.functionName,
        args: tx.args,
        account: address,
        chain: mainnet,
      })
      setState({
        busy: true,
        status: `Confirm ${tx.label.toLowerCase()} in your wallet.`,
      })
      const hash = await wallet.writeContract(request)
      submitted = hash
      remember(hash, tx.label)
      setState({
        busy: true,
        hash,
        label: tx.label,
        status: `${tx.label} submitted. Waiting for Ethereum confirmation…`,
      })
      let cancelled = false
      const receipt = await client.waitForTransactionReceipt({
        hash,
        confirmations: 1,
        timeout: 180_000,
        onReplaced: ({ reason, transaction }) => {
          cancelled = reason === 'cancelled'
          submitted = transaction.hash
          remember(transaction.hash, tx.label)
          setState({
            busy: true,
            hash: transaction.hash,
            label: tx.label,
            status: cancelled
              ? 'Checking cancellation…'
              : 'Transaction replaced. Waiting for confirmation…',
          })
        },
      })
      return await finish(receipt, tx.label, cancelled)
    } catch (error) {
      setState((previous) => ({
        ...previous,
        busy: !!submitted,
        uncertain: !!submitted,
        label: tx.label,
        status: submitted
          ? 'Confirmation was not completed here. Check the transaction before sending another.'
          : '',
        error,
      }))
      return false
    }
  }
  return (
    <TransactionContext.Provider
      value={{
        ...state,
        run,
        check,
        resetPending: () => {
          if (!state.uncertain) return
          remember()
          setState({
            busy: false,
            status:
              'Local transaction status cleared. This does not cancel a transaction already submitted to Ethereum.',
          })
        },
        clear: () => {
          if (!state.busy) setState({ busy: false, status: '' })
        },
      }}
    >
      {children}
    </TransactionContext.Provider>
  )
}
