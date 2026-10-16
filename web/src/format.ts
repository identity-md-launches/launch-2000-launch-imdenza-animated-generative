import { BaseError, formatUnits, getAddress, type Address } from 'viem'

export const shortAddress = (address: string) =>
  `${getAddress(address).slice(0, 6)}…${address.slice(-4)}`
export const explorer = (
  type: 'address' | 'tx' | 'block',
  value: string | number,
) => `https://etherscan.io/${type}/${value}`
export const opensea = (id?: number) =>
  id
    ? `https://opensea.io/assets/ethereum/0xd7fb8c680f9291c0f164c00dc4ae03624a6c76ce/${id}`
    : 'https://opensea.io/collection/imdenza'
export const sameAddress = (a: string, b: string) =>
  a.toLowerCase() === b.toLowerCase()
export const number = (n: number | bigint) => Number(n).toLocaleString('en-US')
export const amount = (n: bigint, decimals = 18) => {
  const value = formatUnits(n, decimals)
  if (n === 0n) return '0'
  if (Number(value) < 0.000001) return '<0.000001'
  return Number(value).toLocaleString('en-US', { maximumFractionDigits: 6 })
}
export const fullAmount = (n: bigint, decimals = 18) => formatUnits(n, decimals)
export const asAddress = (s: string) => getAddress(s) as Address
export function readableError(error: unknown): string {
  const message =
    error instanceof BaseError
      ? error.shortMessage
      : error instanceof Error
        ? error.message
        : 'The request did not complete.'
  if (/reject|denied|cancel/i.test(message))
    return 'Request declined in your wallet. You can try again when ready.'
  if (/provider not found|ProviderNotFound|ConnectorNotFound/i.test(message))
    return 'No browser wallet was found. Open this page in a wallet browser or choose Coinbase Wallet.'
  if (/SoldOut/i.test(message))
    return 'All 3,333 pieces have been minted. Explore the collection instead.'
  if (/AlreadyClaimed|TokenAlreadyUsed/i.test(message))
    return 'This free claim has already been used. Refresh your eligibility.'
  if (/insufficient funds/i.test(message))
    return 'Your wallet needs ETH for the network fee. Add ETH and try again.'
  if (/NotTokenOwner|NotOwnerOfAll/i.test(message))
    return 'Ownership has changed. Refresh your wallet’s pieces and try again.'
  if (/NotConfigured/i.test(message))
    return 'The Identity MD claim route is not configured on chain yet.'
  if (/timeout|fetch|HTTP|network|limit|rate/i.test(message))
    return 'The Ethereum connection is busy. Try again, or choose another RPC in Connection settings.'
  return message.length > 220 ? `${message.slice(0, 217)}…` : message
}
