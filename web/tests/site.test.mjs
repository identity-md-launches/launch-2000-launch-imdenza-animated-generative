import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { chromium, webkit } from 'playwright'
import AxeBuilder from '@axe-core/playwright'
import { preview } from './preview.mjs'

let server, browser
async function newPage(options) {
  const context = await browser.newContext(options)
  const page = await context.newPage()
  page.setDefaultTimeout(15_000)
  return page
}
const results = { viewports: [], axe: [], limitations: [] }
const output = new URL(
  '../../test/scratch/browser-validation/',
  import.meta.url,
)
before(async () => {
  await mkdir(output, { recursive: true })
  server = await preview()
  browser = await chromium.launch({ headless: true })
})
after(async () => {
  await browser?.close()
  await server?.close()
  await writeFile(
    new URL('results.json', output),
    JSON.stringify(results, null, 2),
  )
})

test('production export has complete local assets and real share image', async () => {
  const page = await newPage()
  const errors = []
  page.on('pageerror', (error) => errors.push(error.message))
  page.on('response', (response) => {
    if (response.url().startsWith(server.url) && response.status() >= 400)
      errors.push(`${response.status()} ${response.url()}`)
  })
  await page.goto(server.url)
  await page.locator('.hero .art img').waitFor()
  await page
    .locator('.live-label')
    .filter({ hasText: 'Live from Ethereum' })
    .waitFor({ timeout: 60_000 })
  assert.match(await page.title(), /IMDenza/)
  const share = await page
    .locator('meta[property="og:image"]')
    .getAttribute('content')
  const response = await page.request.get(new URL(share, server.url).href)
  assert.equal(response.status(), 200)
  assert.ok((await response.body()).length > 10_000)
  assert.deepEqual(errors, [])
  await page.close()
})

test('responsive routes, semantic audit, first-screen product and no overflow', async () => {
  const page = await newPage()
  for (const width of [320, 390, 768, 1440]) {
    await page.setViewportSize({ width, height: 844 })
    for (const path of [
      '',
      '#/gallery',
      '#/mint',
      '#/piece/1',
      '#/collection',
      '#/system',
      '#/about',
    ]) {
      await page.goto(server.url + path)
      await page.locator('h1').waitFor()
      await page.evaluate(() => document.fonts.ready)
      const boxes = await page.evaluate(() => ({
        viewport: innerWidth,
        scroll: document.documentElement.scrollWidth,
      }))
      assert.ok(
        boxes.scroll <= boxes.viewport,
        `${path} overflows at ${width}: ${JSON.stringify(boxes)}`,
      )
      assert.equal(await page.locator('h1').count(), 1)
      if (width === 390 && path === '') {
        const art = await page.locator('.hero .art').boundingBox()
        const action = await page
          .getByRole('link', { name: 'Explore the collection', exact: true })
          .boundingBox()
        assert.ok(art.y + art.height < 844, 'Artwork fits first screen at 390')
        assert.ok(
          action.y + action.height < 844,
          'Primary action fits first screen at 390',
        )
      }
      if ([390, 1440].includes(width)) {
        await page.screenshot({
          path: new URL(
            `${width}-${path.replace(/[^a-z0-9]/g, '') || 'home'}.png`,
            output,
          ).pathname,
          fullPage: true,
        })
      }
      if (width === 390) {
        const audit = await new AxeBuilder({ page })
          .withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'])
          .analyze()
        results.axe.push({
          path: path || '/',
          violations: audit.violations.map((v) => ({
            id: v.id,
            impact: v.impact,
            nodes: v.nodes.map((n) => n.target),
          })),
        })
        assert.equal(
          audit.violations.length,
          0,
          `Accessibility violations on ${path}: ${JSON.stringify(results.axe.at(-1))}`,
        )
      }
      results.viewports.push({ path: path || '/', width, overflow: false })
    }
  }
  await page.close()
})

test('gallery filtering, empty result recovery, search, traits, SVG download and modal', async () => {
  const page = await newPage({ viewport: { width: 1440, height: 900 } })
  await page.goto(server.url + '#/gallery')
  await page.locator('.piece-card').first().waitFor({ timeout: 60_000 })
  await page.getByLabel('Palette', { exact: true }).selectOption('7')
  await page
    .getByRole('heading', { name: 'No pieces match these filters.' })
    .waitFor({ timeout: 60_000 })
  await page
    .getByRole('button', { name: 'Clear filters', exact: true })
    .first()
    .click()
  await page.locator('.piece-card').first().waitFor()
  await page.getByLabel('Find a piece', { exact: true }).fill('0')
  await page.getByRole('button', { name: 'Find piece', exact: true }).click()
  await page
    .getByRole('alert')
    .filter({ hasText: 'Enter a minted piece ID' })
    .waitFor()
  await page.getByLabel('Find a piece', { exact: true }).fill('1')
  await page.getByRole('button', { name: 'Find piece', exact: true }).click()
  await page.waitForURL('**/#/piece/1')
  await page.locator('.traits').waitFor({ timeout: 60_000 })
  for (const label of [
    'Scale',
    'Turbulence',
    'Density',
    'Palette',
    'Pulse influence',
    'Contributing job range',
  ])
    assert.ok(await page.getByText(label, { exact: true }).isVisible())
  await page.getByRole('button', { name: 'Expand view', exact: true }).click()
  assert.equal(await page.locator('dialog[open]').count(), 1)
  await page.keyboard.press('Escape')
  assert.equal(await page.locator('dialog[open]').count(), 0)
  assert.equal(
    await page.evaluate(() => document.activeElement?.textContent),
    'Expand view ',
  )
  await page.waitForFunction(
    () => !document.querySelector('.piece-actions button').disabled,
  )
  const downloaded = page.waitForEvent('download')
  await page.getByRole('button', { name: 'Download animated SVG' }).click()
  const download = await downloaded
  const path = await download.path()
  const svg = await readFile(path, 'utf8')
  assert.ok(
    svg.startsWith('<svg') &&
      svg.includes('@keyframes') &&
      svg.endsWith('</svg>'),
  )
  assert.equal(download.suggestedFilename(), 'IMDenza-1.svg')
  await page.goto(server.url + '#/piece/3333')
  await page
    .getByRole('heading', { name: 'This piece hasn’t been minted.' })
    .waitFor({ timeout: 60_000 })
  await page.close()
})

test('wallet sheet has one modal, keyboard focus trap, dismissal and graceful rejection', async () => {
  const page = await newPage({ viewport: { width: 390, height: 844 } })
  await page.goto(server.url + '#/mint')
  await page.getByRole('button', { name: 'Free claims', exact: true }).click()
  await page.getByRole('button', { name: 'Check my eligibility' }).click()
  const dialog = page.getByRole('dialog')
  await dialog.waitFor()
  assert.equal(await page.locator('dialog[open]').count(), 1)
  await page.keyboard.press('Tab')
  assert.equal(
    await page.evaluate(() => document.activeElement?.closest('dialog')?.open),
    true,
  )
  await page.keyboard.press('Shift+Tab')
  assert.equal(
    await page.evaluate(() => document.activeElement?.closest('dialog')?.open),
    true,
  )
  await page.keyboard.press('Escape')
  assert.equal(await page.locator('dialog[open]').count(), 0)
  assert.equal(
    await page
      .getByRole('button', { name: 'Check my eligibility' })
      .evaluate((el) => el === document.activeElement),
    true,
  )
  await page
    .getByRole('button', { name: 'Connect wallet', exact: true })
    .click()
  await page
    .getByRole('button', { name: 'Browser wallet', exact: true })
    .click()
  await page.locator('dialog .notice.error').waitFor({ timeout: 30_000 })
  assert.equal(
    await page
      .getByRole('button', { name: 'Browser wallet', exact: true })
      .isEnabled(),
    true,
  )
  const audit = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'])
    .analyze()
  results.axe.push({
    path: 'wallet-dialog-error',
    violations: audit.violations.map((v) => ({
      id: v.id,
      nodes: v.nodes.map((n) => n.target),
    })),
  })
  assert.equal(audit.violations.length, 0, JSON.stringify(results.axe.at(-1)))
  await page.close()
})

test('mobile wallet links and reduced-motion art', async () => {
  const page = await newPage({
    viewport: { width: 390, height: 844 },
    userAgent:
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1',
    reducedMotion: 'reduce',
  })
  await page.goto(server.url)
  await page
    .getByRole('button', { name: 'Play animation', exact: true })
    .waitFor()
  const src = await page.locator('.hero .art img').getAttribute('src')
  assert.match(decodeURIComponent(src), /animation-play-state:paused!important/)
  assert.match(decodeURIComponent(src), /prefers-reduced-motion:reduce/)
  await page
    .getByRole('button', { name: 'Connect wallet', exact: true })
    .click()
  for (const wallet of ['MetaMask', 'Coinbase Wallet', 'Rabby', 'Phantom'])
    assert.ok(
      await page
        .getByRole('link', { name: `Open in ${wallet}`, exact: true })
        .isVisible(),
    )
  assert.ok(
    await page
      .getByRole('button', { name: 'Coinbase Smart Wallet', exact: true })
      .isVisible(),
  )
  assert.equal(
    await page
      .getByRole('button', { name: 'Browser wallet', exact: true })
      .count(),
    0,
  )
  const rabby = new URL(
    await page
      .getByRole('link', { name: 'Open in Rabby', exact: true })
      .getAttribute('href'),
  )
  assert.equal(rabby.searchParams.get('_cmd'), 'open-dapp')
  assert.equal(rabby.searchParams.get('dapp'), page.url())
  await page.close()
})

test('offline reads keep a labelled artwork snapshot and a usable retry path', async () => {
  const page = await newPage({ viewport: { width: 390, height: 844 } })
  await page.route(
    /^https:\/\/(ethereum-rpc.publicnode.com|eth.drpc.org)\/?$/,
    (route) =>
      route.fulfill({
        status: 503,
        contentType: 'application/json',
        body: '{"error":"Test-only RPC outage"}',
      }),
  )
  await page.goto(server.url)
  await page
    .getByText('On-chain snapshot · live read unavailable', { exact: true })
    .waitFor({ timeout: 60_000 })
  assert.ok(
    await page
      .locator('.hero .art img')
      .evaluate((img) => img.complete && img.naturalWidth > 0),
  )
  await page.locator('.connection-error').waitFor()
  assert.ok(
    await page
      .locator('.connection-error')
      .getByRole('button', { name: 'Try again', exact: true })
      .isEnabled(),
  )
  await page
    .locator('.site-footer')
    .getByRole('button', { name: 'Connection settings', exact: true })
    .click()
  assert.ok(
    await page
      .getByRole('dialog')
      .getByLabel('Custom Ethereum RPC (optional)')
      .isVisible(),
  )
  await page.keyboard.press('Escape')
  await page
    .getByRole('button', { name: 'Connect wallet', exact: true })
    .click()
  assert.equal(await page.locator('dialog[open]').count(), 1)
  await page.close()
})

test('200% CSS text enlargement reflows at 390 without horizontal scrolling', async () => {
  const page = await newPage({ viewport: { width: 390, height: 844 } })
  for (const path of [
    '',
    '#/gallery',
    '#/mint',
    '#/piece/1',
    '#/collection',
    '#/system',
    '#/about',
  ]) {
    await page.goto(server.url + path)
    await page.locator('h1').waitFor()
    await page.evaluate(() => {
      document.documentElement.style.fontSize = '32px'
    })
    assert.equal(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
      true,
      `Text enlargement overflows ${path}`,
    )
  }
  await page.close()
})

test('WebKit launch and primary navigation, if host libraries are installed', async (t) => {
  let engine
  try {
    engine = await webkit.launch({ headless: true })
  } catch (error) {
    results.limitations.push(
      `WebKit did not launch: ${error.message.slice(0, 240)}`,
    )
    t.skip(
      'WebKit host shared libraries are unavailable; see validation limitations.',
    )
    return
  }
  try {
    const page = await engine.newPage({ viewport: { width: 390, height: 844 } })
    await page.goto(server.url)
    await page
      .getByRole('link', { name: 'Explore the collection', exact: true })
      .click()
    await page.locator('.piece-card').first().waitFor({ timeout: 60_000 })
    await page.locator('.piece-card > a').first().click()
    await page.getByRole('button', { name: 'Expand view', exact: true }).click()
    await page.keyboard.press('Escape')
    assert.equal(await page.locator('dialog[open]').count(), 0)
  } finally {
    await engine.close()
  }
})
