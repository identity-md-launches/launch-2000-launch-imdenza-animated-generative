// Explicitly simulated wallet/receipt tests. This file never broadcasts a transaction.
// Contract code and artwork are fetched read-only from the actual deployment; balances,
// NFT eligibility and receipts are controlled fixtures, isolated to Playwright routes.
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { chromium } from 'playwright'
import {
  createPublicClient,
  http,
  decodeFunctionData,
  encodeFunctionResult,
  encodeEventTopics,
  encodeAbiParameters,
  parseAbi,
  toHex,
} from 'viem'
import { collectionAbi, distributorAbi } from '../src/generated/abis.ts'
import { preview } from './preview.mjs'

const deployment = JSON.parse(
  await readFile(new URL('../src/generated/deployment.json', import.meta.url)),
)
const collection = deployment.contracts.find(
  (c) => c.name === 'IMDenza',
).address
const distributor = deployment.distributor.address
const tokenA = '0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7'
const tokenB = '0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127'
const identity = '0x0000ec93127baa929e58e97dd0095a2bfb38ec1d'
const artBlocks = '0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270'
const tokenAbi = parseAbi([
  'function balanceOf(address) view returns(uint256)',
  'function decimals() view returns(uint8)',
  'function allowance(address,address) view returns(uint256)',
  'function approve(address,uint256) returns(bool)',
  'function tokensOfOwner(address) view returns(uint256[])',
  'function tokenOfOwnerByIndex(address,uint256) view returns(uint256)',
  'function ownerOf(uint256) view returns(address)',
])
const live = createPublicClient({
  transport: http('https://ethereum-rpc.publicnode.com', { timeout: 30_000 }),
})
const price = 69_000_000_000_000_000n
let browser, server, owner, liveBlock
before(async () => {
  owner = await live.readContract({
    address: collection,
    abi: collectionAbi,
    functionName: 'ownerOf',
    args: [1n],
  })
  liveBlock = await live.getBlockNumber()
  browser = await chromium.launch({ headless: true })
  server = await preview()
})
after(async () => {
  await browser?.close()
  await server?.close()
})

async function scenario({
  wrongNetwork = false,
  rejectConnect = false,
  flags = 0,
  imdEligible = true,
  rejectedWrite = false,
  supply = 1,
} = {}) {
  const page = await browser.newPage({
    viewport: { width: 1440, height: 1000 },
  })
  const model = {
    allowance: 0n,
    receipts: new Map(),
    calls: [],
    flags,
    supply,
    pending: 10_000_000_000_000_000n,
  }
  await page.addInitScript(
    ({ owner, wrongNetwork, rejectConnect, rejectedWrite }) => {
      const listeners = {}
      const state = {
        connected: false,
        chain: wrongNetwork ? '0x89' : '0x1',
        rejectConnect,
        rejectedWrite,
        sends: [],
        switches: [],
      }
      window.__walletTest = state
      const emit = (event, value) =>
        (listeners[event] ?? []).forEach((fn) => fn(value))
      const provider = {
        on(event, fn) {
          ;(listeners[event] ??= []).push(fn)
        },
        removeListener(event, fn) {
          listeners[event] = (listeners[event] ?? []).filter((f) => f !== fn)
        },
        async request({ method, params }) {
          if (method === 'eth_requestAccounts') {
            if (state.rejectConnect) {
              state.rejectConnect = false
              throw Object.assign(new Error('User rejected request'), {
                code: 4001,
              })
            }
            state.connected = true
            return [owner]
          }
          if (method === 'eth_accounts') return state.connected ? [owner] : []
          if (method === 'eth_chainId') return state.chain
          if (method === 'wallet_switchEthereumChain') {
            state.switches.push(params[0])
            state.chain = params[0].chainId
            emit('chainChanged', state.chain)
            return null
          }
          if (method === 'wallet_addEthereumChain') return null
          if (method === 'wallet_requestPermissions')
            return [{ parentCapability: 'eth_accounts' }]
          if (method === 'wallet_revokePermissions') {
            state.connected = false
            return null
          }
          if (method === 'eth_sendTransaction') {
            if (state.rejectedWrite) {
              state.rejectedWrite = false
              throw Object.assign(new Error('User rejected request'), {
                code: 4001,
              })
            }
            state.sends.push(params[0])
            return `0x${state.sends.length.toString(16).padStart(64, '0')}`
          }
          throw Object.assign(
            new Error(`Unsupported test-wallet method: ${method}`),
            { code: 4200 },
          )
        },
      }
      window.ethereum = provider
      const detail = {
        info: {
          uuid: '7bd65fd0-a3b6-4e8d-a5d8-60ba588e3b14',
          name: 'Test wallet',
          icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28"><rect width="28" height="28" fill="navy"/></svg>',
          rdns: 'test.imdenza.wallet',
        },
        provider,
      }
      const announce = () =>
        window.dispatchEvent(
          new CustomEvent('eip6963:announceProvider', { detail }),
        )
      window.addEventListener('eip6963:requestProvider', announce)
      announce()
    },
    { owner, wrongNetwork, rejectConnect, rejectedWrite },
  )

  const reply = async (request) => {
    const { method, params = [] } = request
    if (method === 'eth_chainId') return '0x1'
    if (method === 'eth_blockNumber') return toHex(liveBlock)
    if (method === 'eth_getTransactionReceipt') {
      const sends = await page.evaluate(() => window.__walletTest.sends)
      const nth = Number(BigInt(params[0])) - 1
      const sent = sends[nth]
      if (!sent) return null
      if (model.receipts.has(params[0])) return model.receipts.get(params[0])
      const abi =
        sent.to.toLowerCase() === tokenA
          ? tokenAbi
          : sent.to.toLowerCase() === distributor.toLowerCase()
            ? distributorAbi
            : collectionAbi
      const call = decodeFunctionData({ abi, data: sent.data })
      model.calls.push({ ...call, to: sent.to, value: sent.value })
      if (call.functionName === 'approve') model.allowance = call.args[1]
      if (call.functionName === 'claim') model.pending = 0n
      const logs = []
      if (
        [
          'mint',
          'claimWithImd',
          'claimWithIdentityMd',
          'claimWithFidenza',
        ].includes(call.functionName)
      ) {
        const topics = encodeEventTopics({
          abi: collectionAbi,
          eventName: 'Minted',
          args: { tokenId: 2n, to: owner },
        })
        const data = encodeAbiParameters(
          [
            { type: 'bytes32' },
            { type: 'bytes32' },
            { type: 'uint256' },
            { type: 'uint8' },
          ],
          [`0x${'12'.repeat(32)}`, `0x${'00'.repeat(32)}`, 0n, 0],
        )
        logs.push({
          address: collection,
          topics,
          data,
          blockNumber: toHex(liveBlock),
          blockHash: `0x${'ab'.repeat(32)}`,
          transactionHash: params[0],
          transactionIndex: '0x0',
          logIndex: '0x0',
          removed: false,
        })
      }
      const receipt = {
        transactionHash: params[0],
        transactionIndex: '0x0',
        blockHash: `0x${'ab'.repeat(32)}`,
        blockNumber: toHex(liveBlock),
        from: owner,
        to: sent.to,
        cumulativeGasUsed: '0x186a0',
        gasUsed: '0x186a0',
        contractAddress: null,
        logs,
        logsBloom: `0x${'00'.repeat(256)}`,
        status: '0x1',
        type: '0x2',
        effectiveGasPrice: '0x1',
      }
      model.receipts.set(params[0], receipt)
      return receipt
    }
    if (method === 'eth_call') {
      const address = params[0].to.toLowerCase()
      const abi =
        address === collection
          ? collectionAbi
          : address === distributor.toLowerCase()
            ? distributorAbi
            : tokenAbi
      let call
      try {
        call = decodeFunctionData({ abi, data: params[0].data })
      } catch {
        /* Swarm read: pass through. */
      }
      if (call) {
        const { functionName, args } = call
        let result
        if (address === collection) {
          if (functionName === 'totalMinted') result = BigInt(model.supply)
          if (functionName === 'claimFlags') result = model.flags
          if (functionName === 'holdsImd') result = imdEligible
          if (
            functionName === 'identityTokenUsed' ||
            functionName === 'fidenzaTokenUsed'
          )
            result = false
          if (
            [
              'mint',
              'claimWithImd',
              'claimWithIdentityMd',
              'claimWithFidenza',
            ].includes(functionName)
          )
            result = 2n
        } else if (address === distributor.toLowerCase()) {
          if (functionName === 'pending') result = model.pending
          if (functionName === 'claim') result = model.pending
          if (functionName === 'distribute') result = 1n
          if (functionName === 'reserved') result = 0n
        } else {
          if (functionName === 'decimals') result = 18
          if (functionName === 'allowance') result = model.allowance
          if (functionName === 'approve') result = true
          if (functionName === 'balanceOf')
            result = [identity, artBlocks].includes(address)
              ? 1n
              : 100n * 10n ** 18n
          if (functionName === 'tokensOfOwner')
            result = address === identity ? [0n] : [78_000_042n]
          if (functionName === 'ownerOf') result = owner
          if (functionName === 'tokenOfOwnerByIndex') result = args[1]
        }
        if (result !== undefined)
          return encodeFunctionResult({ abi, functionName, result })
      }
    }
    if (
      ![
        'eth_call',
        'eth_getCode',
        'eth_getBalance',
        'eth_getLogs',
        'eth_getBlockByNumber',
        'eth_getTransactionByHash',
      ].includes(method)
    )
      throw new Error(`Unexpected RPC method; refuses to broadcast: ${method}`)
    return await live.request({ method, params })
  }
  await page.route(
    /^https:\/\/(ethereum-rpc.publicnode.com|eth.drpc.org)\/?$/,
    async (route) => {
      const request = route.request().postDataJSON()
      const batch = Array.isArray(request) ? request : [request]
      const result = await Promise.all(
        batch.map(async (rpc) => {
          try {
            return { jsonrpc: '2.0', id: rpc.id, result: await reply(rpc) }
          } catch (error) {
            return {
              jsonrpc: '2.0',
              id: rpc.id,
              error: { code: -32000, message: error.message },
            }
          }
        }),
      )
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(Array.isArray(request) ? result : result[0]),
      })
    },
  )
  return {
    page,
    model,
    connect: async () => {
      await page
        .getByRole('banner')
        .getByRole('button', { name: 'Connect wallet', exact: true })
        .click()
      assert.equal(
        await page
          .getByRole('button', { name: 'Browser wallet', exact: true })
          .count(),
        0,
        'Generic injected row is hidden for a named provider',
      )
      await page
        .getByRole('button', { name: 'Test wallet', exact: true })
        .click()
    },
  }
}

test('EIP-6963 cancellation recovers; wrong chain switches once and reconnects', async () => {
  const { page, connect } = await scenario({
    wrongNetwork: true,
    rejectConnect: true,
  })
  await page.goto(server.url + '#/mint')
  await connect()
  await page
    .getByText('Request declined in your wallet. You can try again when ready.')
    .waitFor()
  assert.ok(
    await page
      .getByRole('button', { name: 'Test wallet', exact: true })
      .isEnabled(),
  )
  await page.getByRole('button', { name: 'Test wallet', exact: true }).click()
  await page
    .getByRole('button', { name: 'Switch to Ethereum', exact: true })
    .waitFor()
  assert.ok(
    await page
      .getByRole('button', { name: 'Approve 0.069 IMD', exact: true })
      .isDisabled(),
  )
  await page
    .getByRole('button', { name: 'Switch to Ethereum', exact: true })
    .click()
  await page.waitForFunction(() => window.__walletTest.chain === '0x1')
  await page.waitForFunction(
    () => !document.querySelector('.mint-panel > button').disabled,
  )
  assert.equal(
    (await page.evaluate(() => window.__walletTest.switches)).length,
    1,
  )
  assert.equal(await page.locator('dialog[open]').count(), 0)
  await page.close()
})

test('public mint approves exactly the price, waits, then sends IMD mint with no ETH payment', async () => {
  const { page, model, connect } = await scenario({ rejectedWrite: true })
  await page.goto(server.url + '#/mint')
  await connect()
  const approve = page.getByRole('button', {
    name: 'Approve 0.069 IMD',
    exact: true,
  })
  await approve.waitFor()
  await page.waitForFunction(
    () => !document.querySelector('.mint-panel > button').disabled,
  )
  await approve.click()
  await page
    .getByText('Request declined in your wallet. You can try again when ready.')
    .waitFor({ timeout: 30_000 })
  assert.ok(await approve.isEnabled())
  await approve.click()
  await page.getByText('IMD approval confirmed.').waitFor({ timeout: 60_000 })
  assert.equal(model.calls.length, 1)
  assert.equal(model.calls[0].functionName, 'approve')
  assert.equal(model.calls[0].args[0].toLowerCase(), collection)
  assert.equal(model.calls[0].args[1], price)
  await page
    .getByRole('button', { name: 'Mint for 0.069 IMD', exact: true })
    .click()
  await page
    .getByText('Mint confirmed. IMDenza #2 is now in your wallet.')
    .waitFor({ timeout: 60_000 })
  assert.equal(model.calls.length, 2)
  assert.equal(model.calls[1].functionName, 'mint')
  assert.equal(model.calls[1].args[0].toLowerCase(), tokenA)
  assert.ok(model.calls.every((c) => !c.value || BigInt(c.value) === 0n))
  assert.equal(
    await page
      .getByRole('link', { name: 'View your new piece' })
      .getAttribute('href'),
    '#/piece/2',
  )
  await page.close()
})

test('all three claim routes validate eligibility and call the exact free-claim methods', async () => {
  for (const [label, method, id] of [
    ['IMD holdings', 'claimWithImd', undefined],
    ['Identity MD', 'claimWithIdentityMd', 0n],
    ['Fidenza', 'claimWithFidenza', 78_000_042n],
  ]) {
    const { page, model, connect } = await scenario()
    await page.goto(server.url + '#/mint')
    await connect()
    await page.getByRole('button', { name: 'Free claims', exact: true }).click()
    const button = page.getByRole('button', {
      name: `Claim with ${label}`,
      exact: true,
    })
    await button.waitFor()
    await page.waitForFunction(
      (label) =>
        [...document.querySelectorAll('button')].some(
          (b) => b.textContent.trim() === `Claim with ${label}` && !b.disabled,
        ),
      label,
    )
    await button.click()
    await page
      .getByRole('link', { name: 'View your new piece' })
      .waitFor({ timeout: 60_000 })
    assert.equal(model.calls[0].functionName, method)
    if (id !== undefined) assert.equal(model.calls[0].args[0], id)
    await page.close()
  }
})

test('consumed claims and sold-out supply disable every mint route', async () => {
  const { page, connect } = await scenario({ flags: 7, supply: 3333 })
  await page.goto(server.url + '#/mint')
  await connect()
  await page
    .getByText('All 3,333 pieces have been minted.', { exact: false })
    .first()
    .waitFor()
  assert.ok(
    await page
      .getByRole('button', { name: 'Collection sold out', exact: true })
      .isDisabled(),
  )
  await page.getByRole('button', { name: 'Free claims', exact: true }).click()
  await page.getByText('Already claimed', { exact: true }).first().waitFor()
  for (const label of ['IMD holdings', 'Identity MD', 'Fidenza'])
    assert.ok(
      await page
        .getByRole('button', { name: `Claim with ${label}`, exact: true })
        .isDisabled(),
    )
  await page.close()
})

test('holder ownership scan, exact pending balance, distribute and current-owner claim', async () => {
  const { page, model, connect } = await scenario()
  await page.goto(server.url + '#/collection')
  await connect()
  await page
    .getByText('Exact balance: 0.01 IMD', { exact: true })
    .waitFor({ timeout: 60_000 })
  await page.setViewportSize({ width: 390, height: 844 })
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
    true,
  )
  await page.screenshot({
    path: new URL(
      '../../test/scratch/simulated-dashboard-390.png',
      import.meta.url,
    ).pathname,
    fullPage: true,
  })
  assert.equal(await page.locator('.collection-section .piece-card').count(), 1)
  await page.getByRole('button', { name: 'Distribute', exact: true }).click()
  await page
    .getByText('IMD distribution confirmed.', { exact: true })
    .waitFor({ timeout: 60_000 })
  await page
    .getByRole('button', { name: 'Claim 0.01 IMD', exact: true })
    .click()
  await page
    .getByText('IMD payout confirmed.', { exact: true })
    .waitFor({ timeout: 60_000 })
  assert.equal(model.calls[0].functionName, 'distribute')
  assert.equal(model.calls[1].functionName, 'claim')
  assert.equal(model.calls[1].args[0].toLowerCase(), tokenA)
  assert.deepEqual(model.calls[1].args[1], [1n])
  await page
    .getByRole('button', { name: 'Nothing to claim yet', exact: true })
    .waitFor()
  assert.ok(
    await page
      .getByRole('button', { name: 'Nothing to claim yet', exact: true })
      .isDisabled(),
  )
  await page.getByLabel('Asset to claim').selectOption('3')
  await page
    .getByText('This asset is not deployed on Ethereum.', { exact: true })
    .waitFor()
  await page.close()
})

test('pending transaction recovery survives reload and has an explicit local reset', async () => {
  const { page, connect } = await scenario()
  await page.addInitScript(() => {
    if (!sessionStorage.getItem('test.pending.initialized')) {
      sessionStorage.setItem('test.pending.initialized', 'yes')
      sessionStorage.setItem(
        'imdenza.pending',
        JSON.stringify({ hash: `0x${'ff'.repeat(32)}`, label: 'Mint' }),
      )
    }
  })
  await page.goto(server.url + '#/mint')
  await connect()
  await page
    .getByRole('button', { name: 'Check transaction status', exact: true })
    .waitFor()
  assert.ok(
    await page
      .getByRole('button', { name: 'Transaction in progress…', exact: true })
      .isDisabled(),
  )
  await page
    .getByRole('button', { name: 'Check transaction status', exact: true })
    .click()
  await page
    .getByText('This transaction is not confirmed here yet.', { exact: false })
    .waitFor()
  await page
    .getByText('Transaction replaced or dropped?', { exact: true })
    .click()
  await page
    .getByRole('button', {
      name: 'Clear local transaction status',
      exact: true,
    })
    .click()
  assert.equal(
    await page.evaluate(() => sessionStorage.getItem('imdenza.pending')),
    null,
  )
  await page
    .getByRole('button', { name: 'Approve 0.069 IMD', exact: true })
    .waitFor()
  assert.ok(
    await page
      .getByRole('button', { name: 'Approve 0.069 IMD', exact: true })
      .isEnabled(),
  )
  await page.close()
})

test('missing token deployment and insufficient free-claim eligibility stay unavailable', async () => {
  const { page, connect } = await scenario({ imdEligible: false })
  await page.goto(server.url + '#/mint')
  await connect()
  await page.getByLabel('Pay with', { exact: true }).selectOption(tokenB)
  await page
    .getByText('This IMD token has no deployed code.', { exact: false })
    .waitFor()
  assert.ok(await page.locator('.mint-panel > button').isDisabled())
  await page.getByRole('button', { name: 'Free claims', exact: true }).click()
  await page.getByText('Not eligible', { exact: true }).waitFor()
  assert.ok(
    await page
      .getByRole('button', { name: 'Claim with IMD holdings', exact: true })
      .isDisabled(),
  )
  const fidenza = page.locator('.claim-route').filter({
    has: page.getByRole('heading', { name: 'Fidenza holder', exact: true }),
  })
  await fidenza.getByText('Check a specific token ID', { exact: true }).click()
  await fidenza
    .getByLabel('Full Art Blocks token ID', { exact: true })
    .fill('77000000')
  await fidenza.getByRole('button', { name: 'Verify', exact: true }).click()
  await fidenza
    .getByText('Fidenza token IDs are 78000000–78999999.', { exact: false })
    .waitFor()
  assert.ok(
    await fidenza
      .getByRole('button', { name: 'Claim with Fidenza', exact: true })
      .isDisabled(),
  )
  await page.close()
})
