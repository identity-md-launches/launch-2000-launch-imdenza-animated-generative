// Recreate the locally bundled 1200 × 630 share card from the real on-chain snapshot.
import { chromium } from 'playwright'
import { readFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
const require = createRequire(import.meta.url)
const snapshot = JSON.parse(
  await readFile(new URL('../src/generated/snapshot.json', import.meta.url)),
)
const fontData = async (path) =>
  `data:font/woff2;base64,${(await readFile(require.resolve(path))).toString('base64')}`
const display = await fontData(
  '@fontsource/instrument-serif/files/instrument-serif-latin-400-normal.woff2',
)
const italic = await fontData(
  '@fontsource/instrument-serif/files/instrument-serif-latin-400-italic.woff2',
)
const body = await fontData(
  '@fontsource/dm-sans/files/dm-sans-latin-400-normal.woff2',
)
const svg = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(snapshot.svg.replace('</style>', '*{animation:none!important}</style>'))}`
const html = `<!doctype html><html lang="en"><meta charset="utf-8"><style>
@font-face{font-family:ShareDisplay;src:url('${display}')}@font-face{font-family:ShareDisplay;src:url('${italic}');font-style:italic}@font-face{font-family:ShareBody;src:url('${body}')}
*{box-sizing:border-box}body{margin:0;background:#171916;color:#f0ede4;width:1200px;height:630px;padding:48px;display:grid;grid-template-columns:1fr 530px;gap:44px;font-family:ShareBody}h1{font:88px/1.05 ShareDisplay;margin:56px 0 28px;letter-spacing:-2px}i{color:#e4af8c}p{font-size:22px;line-height:1.5;color:#adafa2;max-width:400px}header{font:42px ShareDisplay}footer{margin-top:44px;font-size:18px;color:#adafa2}img{width:530px;height:530px;display:block;margin-top:2px}
</style><section><header>IMDenza</header><h1>The swarm,<br><i>set in motion.</i></h1><p>3,333 animated flow fields,<br>written on Ethereum.</p><footer>Fully on-chain generative art</footer></section><img alt="IMDenza #1" src="${svg}"></html>`
const browser = await chromium.launch({ headless: true })
try {
  const page = await browser.newPage({
    viewport: { width: 1200, height: 630 },
    deviceScaleFactor: 1,
  })
  await page.setContent(html)
  await page.evaluate(() => document.fonts.ready)
  await page.screenshot({
    path: new URL('../public/share.png', import.meta.url).pathname,
  })
  console.log(
    'Created public/share.png from on-chain artwork #1 at block',
    snapshot.block,
  )
} finally {
  await browser.close()
}
