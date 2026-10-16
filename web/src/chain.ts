import {
  createPublicClient,
  fallback,
  http,
  keccak256,
  parseAbi,
  zeroAddress,
  type Address,
} from 'viem'
import { mainnet } from 'viem/chains'
import { createConfig } from 'wagmi'
import { coinbaseWallet, injected, walletConnect } from 'wagmi/connectors'
import { collectionAbi, distributorAbi, swarmAbi } from './generated/abis'
import deployment from './generated/deployment.json'
import { sameAddress } from './format'

export const COLLECTION = deployment.contracts.find(
  (c) => c.name === 'IMDenza',
)!.address as Address
export const SWARM = deployment.contracts.find(
  (c) => c.name === 'SwarmHistory',
)!.address as Address
export const IDENTITY = '0x0000ec93127baa929e58e97dd0095a2bfb38ec1d' as const
export const IMD_A = '0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7' as const
export const IMD_B = '0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127' as const
export const ART_BLOCKS = '0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270' as const
export const REPO =
  'https://github.com/identity-md-launches/launch-2000-launch-imdenza-animated-generative'
export const JOB =
  'https://explorer.imd.fun/jobs/39a66ffb-504c-4e61-a345-3a8d585ecbf8'
export const RPC_URLS = [
  'https://ethereum-rpc.publicnode.com',
  'https://eth.drpc.org',
] as const
export const erc20Abi = parseAbi([
  'function balanceOf(address) view returns (uint256)',
  'function allowance(address,address) view returns (uint256)',
  'function approve(address,uint256) returns (bool)',
  'function decimals() view returns (uint8)',
])
export const erc721Abi = parseAbi([
  'function balanceOf(address) view returns (uint256)',
  'function ownerOf(uint256) view returns (address)',
  'function tokenOfOwnerByIndex(address,uint256) view returns (uint256)',
  'function tokensOfOwner(address) view returns (uint256[])',
])

function storedRpc() {
  try {
    const value = localStorage.getItem('imdenza.rpc')
    return value && new URL(value).protocol === 'https:' ? value : undefined
  } catch {
    return undefined
  }
}
export const customRpc = storedRpc()
const transport = () =>
  fallback(
    [
      ...(customRpc
        ? [
            http(customRpc, {
              timeout: 25_000,
              retryCount: 1,
              batch: { batchSize: 40, wait: 20 },
            }),
          ]
        : []),
      ...RPC_URLS.map((url) =>
        http(url, {
          timeout: 25_000,
          retryCount: 1,
          batch: { batchSize: 40, wait: 20 },
        }),
      ),
    ],
    { rank: false },
  )
export const client = createPublicClient({
  chain: mainnet,
  transport: transport(),
})
export const readCollection = {
  address: COLLECTION,
  abi: collectionAbi,
} as const
export const readSwarm = { address: SWARM, abi: swarmAbi } as const
export function makeWalletConfig(projectId = '') {
  return createConfig({
    chains: [mainnet],
    multiInjectedProviderDiscovery: true,
    connectors: [
      injected(),
      ...(projectId
        ? [
            walletConnect({
              projectId,
              showQrModal: true,
              metadata: {
                name: 'IMDenza',
                description:
                  'Animated on-chain flow fields, shaped by the IMD swarm.',
                url: location.href.split('#')[0],
                icons: [new URL('./favicon.svg', location.href).href],
              },
            }),
          ]
        : []),
      coinbaseWallet({
        appName: 'IMDenza',
        appLogoUrl: new URL('./favicon.svg', location.href).href,
      }),
    ],
    transports: { [mainnet.id]: transport() },
  })
}
export async function collectionState() {
  const block = await client.getBlockNumber()
  const [minted, max, jobs, pulse, distributor, identity, weth] =
    await Promise.all([
      client.readContract({
        ...readCollection,
        functionName: 'totalMinted',
        blockNumber: block,
      }),
      client.readContract({
        ...readCollection,
        functionName: 'MAX_SUPPLY',
        blockNumber: block,
      }),
      client.readContract({
        ...readSwarm,
        functionName: 'jobCount',
        blockNumber: block,
      }),
      client.readContract({
        ...readSwarm,
        functionName: 'pulse',
        blockNumber: block,
      }),
      client.readContract({
        ...readCollection,
        functionName: 'distributor',
        blockNumber: block,
      }),
      client.readContract({
        ...readCollection,
        functionName: 'identityMdCollection',
        blockNumber: block,
      }),
      client.readContract({
        ...readCollection,
        functionName: 'WETH',
        blockNumber: block,
      }),
    ])
  return {
    minted: Number(minted),
    max: Number(max),
    jobs: Number(jobs),
    pulse: Number(pulse),
    distributor,
    identity,
    weth,
    block,
    readAt: Date.now(),
  }
}
export type CollectionState = Awaited<ReturnType<typeof collectionState>>
export async function verifyDeployment() {
  if ((await client.getChainId()) !== 1)
    throw new Error(
      'This RPC is not Ethereum mainnet. Choose an Ethereum RPC in Connection settings.',
    )
  await Promise.all(
    deployment.contracts.map(async (contract) => {
      const code = await client.getCode({
        address: contract.address as Address,
      })
      if (
        !code ||
        code === '0x' ||
        keccak256(code) !== contract.runtimeCodeHash
      )
        throw new Error(
          `${contract.name} code could not be verified. Transactions are disabled; retry the Ethereum connection.`,
        )
    }),
  )
  const distributor = await client.readContract({
    ...readCollection,
    functionName: 'distributor',
  })
  const code = await client.getCode({ address: distributor })
  if (
    !code ||
    keccak256(code) !== deployment.distributor.runtimeCodeHash ||
    !sameAddress(
      await client.readContract({
        address: distributor,
        abi: distributorAbi,
        functionName: 'nft',
      }),
      COLLECTION,
    )
  )
    throw new Error(
      'The holder distributor could not be verified. Retry the Ethereum connection.',
    )
  return true
}
export async function getPiece(id: number) {
  const block = await client.getBlockNumber()
  const [traits, data, owner] = await Promise.all([
    client.readContract({
      ...readCollection,
      functionName: 'traits',
      args: [BigInt(id)],
      blockNumber: block,
    }),
    client.readContract({
      ...readCollection,
      functionName: 'tokenData',
      args: [BigInt(id)],
      blockNumber: block,
    }),
    client.readContract({
      ...readCollection,
      functionName: 'ownerOf',
      args: [BigInt(id)],
      blockNumber: block,
    }),
  ])
  return { id, traits, data, owner, block }
}
export type Piece = Awaited<ReturnType<typeof getPiece>>
export const paletteNames = [
  'Ember',
  'Harbor',
  'Meadow',
  'Noir',
  'Linen',
  'Candy',
  'Terracotta',
  'Glacier',
]
export const scaleNames = ['Small', 'Medium', 'Large', 'Jumbo']
export const turbulenceNames = ['None', 'Low', 'Mid', 'High']
export const densityNames = ['Sparse', 'Medium', 'Dense']
export const collisionNames = ['Tight', 'Standard', 'Airy']

export async function ownedPieces(
  address: Address,
  minted: number,
  onProgress?: (done: number) => void,
) {
  const ids: number[] = []
  const block = await client.getBlockNumber()
  for (let start = 1; start <= minted; start += 60) {
    const batch = Array.from(
      { length: Math.min(60, minted - start + 1) },
      (_, i) => start + i,
    )
    const owners = await Promise.all(
      batch.map((id) =>
        client.readContract({
          ...readCollection,
          functionName: 'ownerOf',
          args: [BigInt(id)],
          blockNumber: block,
        }),
      ),
    )
    owners.forEach((owner, i) => {
      if (sameAddress(owner, address)) ids.push(batch[i])
    })
    onProgress?.(Math.min(start + batch.length - 1, minted))
  }
  return ids
}

// address(0) is the distributor's defined native-ETH asset identifier, never a recipient.
export const nativeAsset = zeroAddress
