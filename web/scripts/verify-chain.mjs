import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { createPublicClient, http, keccak256, toHex, parseAbi } from 'viem'
import { mainnet } from 'viem/chains'
import { fileURLToPath } from 'node:url'
import { resolve, dirname } from 'node:path'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const canonical = (value) =>
  Array.isArray(value)
    ? value.map(canonical)
    : value && typeof value === 'object'
      ? Object.fromEntries(
          Object.keys(value)
            .sort()
            .map((key) => [key, canonical(value[key])]),
        )
      : value
const json = async (path) =>
  JSON.parse(await readFile(resolve(root, path), 'utf8'))
const write = async (path, value) =>
  writeFile(resolve(root, path), JSON.stringify(value, null, 2) + '\n')
const generate = process.argv.includes('--generate')
const pinned = generate
  ? await json('.imd/reads/deployment.json')
  : await json('web/src/generated/deployment.json')
const client = createPublicClient({
  chain: mainnet,
  transport: http('https://ethereum-rpc.publicnode.com', { timeout: 60_000 }),
})
if ((await client.getChainId()) !== 1) throw new Error('Wrong chain')
const block = await client.getBlockNumber()
const evidence = []
let collectionAbi
for (const contract of pinned.contracts) {
  const code = await client.getCode({
    address: contract.address,
    blockNumber: block,
  })
  if (!code || code === '0x') throw new Error(`${contract.name}: no code`)
  const runtimeCodeHash = keccak256(code)
  if (generate) {
    const artifact = await json(
      `test/scratch/forge-out/${contract.name}.sol/${contract.name}.json`,
    )
    const hash = keccak256(
      toHex(JSON.stringify(canonical(artifact.abi))),
    ).slice(2)
    if (hash !== contract.abiHash)
      throw new Error(
        `${contract.name} ABI mismatch: ${hash} != ${contract.abiHash}`,
      )
    const expected = artifact.deployedBytecode.object.replace(/^0x/, '')
    let actual = code.slice(2)
    for (const slots of Object.values(
      artifact.deployedBytecode.immutableReferences ?? {},
    )) {
      for (const { start, length } of slots)
        actual =
          actual.slice(0, start * 2) +
          '0'.repeat(length * 2) +
          actual.slice((start + length) * 2)
    }
    if (actual !== expected)
      throw new Error(
        `${contract.name}: compiled runtime differs outside immutable slots`,
      )
    if (contract.name === 'IMDenza') collectionAbi = artifact.abi
  } else if (runtimeCodeHash !== contract.runtimeCodeHash)
    throw new Error(`${contract.name}: code hash mismatch`)
  evidence.push({
    name: contract.name,
    address: contract.address,
    abiHash: contract.abiHash,
    runtimeCodeHash,
  })
  console.log(
    `${contract.name}: ${generate ? 'pinned ABI + compiled runtime + ' : ''}live code verified`,
  )
}
if (generate) {
  const address = evidence.find((c) => c.name === 'IMDenza').address
  const distributor = await client.readContract({
    address,
    abi: collectionAbi,
    functionName: 'distributor',
    blockNumber: block,
  })
  const artifact = await json(
    'test/scratch/forge-out/IMDenzaDistributor.sol/IMDenzaDistributor.json',
  )
  const code = await client.getCode({
    address: distributor,
    blockNumber: block,
  })
  let actual = code.slice(2)
  for (const slots of Object.values(
    artifact.deployedBytecode.immutableReferences ?? {},
  ))
    for (const { start, length } of slots)
      actual =
        actual.slice(0, start * 2) +
        '0'.repeat(length * 2) +
        actual.slice((start + length) * 2)
  if (actual !== artifact.deployedBytecode.object.replace(/^0x/, ''))
    throw new Error('Distributor bytecode mismatch')
  await mkdir(resolve(root, 'web/src/generated'), { recursive: true })
  const swarmArtifact = await json(
    'test/scratch/forge-out/SwarmHistory.sol/SwarmHistory.json',
  )
  await writeFile(
    resolve(root, 'web/src/generated/abis.ts'),
    '// Generated from the pinned Solidity source with solc 0.8.26. See scripts/verify-chain.mjs.\n' +
      [
        ['collectionAbi', collectionAbi],
        ['distributorAbi', artifact.abi],
        ['swarmAbi', swarmArtifact.abi],
      ]
        .map(
          ([name, abi]) =>
            `export const ${name} = ${JSON.stringify(abi)} as const`,
        )
        .join('\n') +
      '\n',
  )
  await write('web/src/generated/deployment.json', {
    sourceCommit: pinned.sourceCommit,
    chainId: 1,
    verifiedAtBlock: block.toString(),
    contracts: evidence,
    distributor: { address: distributor, runtimeCodeHash: keccak256(code) },
  })
  const minted = await client.readContract({
    address,
    abi: collectionAbi,
    functionName: 'totalMinted',
    blockNumber: block,
  })
  if (minted > 0n) {
    const svg = await client.readContract({
      address,
      abi: collectionAbi,
      functionName: 'svg',
      args: [1n],
      blockNumber: block,
    })
    await write('web/src/generated/snapshot.json', {
      tokenId: 1,
      block: block.toString(),
      source: address,
      svg,
    })
  }
} else {
  const address = evidence.find((c) => c.name === 'IMDenza').address
  const distributor = await client.readContract({
    address,
    abi: parseAbi(['function distributor() view returns(address)']),
    functionName: 'distributor',
  })
  if (distributor.toLowerCase() !== pinned.distributor.address.toLowerCase())
    throw new Error('Distributor address mismatch')
  const code = await client.getCode({ address: distributor })
  if (!code || keccak256(code) !== pinned.distributor.runtimeCodeHash)
    throw new Error('Distributor code mismatch')
  console.log('IMDenzaDistributor: derived address and live code verified')
}
console.log(
  `Ethereum block ${block}: ${evidence.length} deployed contracts verified. No transactions sent.`,
)
