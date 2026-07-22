import assert from 'node:assert/strict'
import test from 'node:test'
import { canonicalAnalytics, canonicalSales, summarizeSales, uniqueCloudKitUserCount } from '../scripts/collect-dashboard-data.mjs'

const sale = (overrides = {}) => ({
  'End Date': '2026-07-20',
  'Country of Sale': 'DE',
  'Currency of Proceeds': 'EUR',
  'Developer Proceeds': '0',
  Units: '1',
  ...overrides,
})

test('Apple app units and in-app purchases are separated by product type', () => {
  const rows = canonicalSales([
    sale({ 'Product Type Identifier': '1F', Units: '12' }),
    sale({ 'Product Type Identifier': 'IA1', Units: '3', 'Developer Proceeds': '1.50' }),
    sale({ 'Product Type Identifier': '7F', Units: '4' }),
    sale({ 'Product Type Identifier': 'IA3', Units: '1' }),
  ])
  const summary = summarizeSales(rows, '2026-07-20')

  assert.equal(summary.classificationStatus, 'complete')
  assert.equal(summary.appUnits, 12)
  assert.equal(summary.inAppPurchaseUnits, 3)
  assert.equal(summary.restoredInAppPurchaseUnits, 1)
  assert.equal(rows[1].proceeds, 4.5)
  assert.equal('appUnits' in rows[2], false)
  assert.equal('inAppPurchaseUnits' in rows[3], false)
})

test('legacy Apple subscription identifier remains classified as an in-app purchase', () => {
  const summary = summarizeSales(canonicalSales([
    sale({ 'Product Type Identifier': '1AY', Units: '1' }),
  ]), '2026-07-20')

  assert.equal(summary.classificationStatus, 'complete')
  assert.equal(summary.inAppPurchaseUnits, 1)
})

test('missing category is reported as a conclusive zero only for a classified report', () => {
  const summary = summarizeSales(canonicalSales([
    sale({ 'Product Type Identifier': '1', Units: '2' }),
  ]), '2026-07-20')

  assert.equal(summary.appUnits, 2)
  assert.equal(summary.inAppPurchaseUnits, 0)
  assert.equal(summary.classificationStatus, 'complete')
})

test('unknown product types keep category totals unavailable instead of guessing zero', () => {
  const summary = summarizeSales(canonicalSales([
    sale({ 'Product Type Identifier': 'FUTURE-TYPE', Units: '2' }),
  ]), '2026-07-20')

  assert.equal(summary.classificationStatus, 'partial')
  assert.equal(summary.appUnits, null)
  assert.equal(summary.inAppPurchaseUnits, null)
  assert.equal(summary.unclassifiedUnits, 2)
  assert.deepEqual(summary.unknownProductTypeIdentifiers, ['FUTURE-TYPE'])
})

test('empty reports and unsupported currencies do not create misleading financial zeroes', () => {
  const empty = summarizeSales([], '2026-07-20')
  const [usd] = canonicalSales([
    sale({ 'Product Type Identifier': 'IA1', Units: '2', 'Developer Proceeds': '1.50', 'Currency of Proceeds': 'USD' }),
  ])

  assert.equal(empty.appUnits, null)
  assert.equal(empty.inAppPurchaseUnits, null)
  assert.equal(empty.refunds, null)
  assert.equal('proceeds' in usd, false)
})

test('completed-bundle credits are not mislabeled as refunds', () => {
  const [credit] = canonicalSales([
    sale({ 'Product Type Identifier': '1F', Units: '-1', CMB: 'CMB-C' }),
  ])

  assert.equal(credit.refunds, 0)
})

test('Apple Analytics generic Counts are classified by report and never turn missing metrics into zero', () => {
  const rows = canonicalAnalytics([
    { __reportName: 'App Sessions Standard', Date: '2026-07-20', Sessions: '8', 'Unique Devices': '5', Territory: 'DE' },
    { __reportName: 'App Store Downloads Standard', Date: '2026-07-20', Counts: '3', 'Download Type': 'First-time Download', Territory: 'DE' },
    { __reportName: 'App Store Installations and Deletions Standard', Date: '2026-07-20', Counts: '2', Event: 'Delete', Territory: 'DE' },
  ])

  assert.deepEqual(rows[0], { date: '2026-07-20', country: 'DE', device: undefined, osVersion: undefined, appVersion: undefined, sessions: 8, activeDevices: 5 })
  assert.equal(rows[1].downloads, 3)
  assert.equal(rows[1].firstTimeDownloads, 3)
  assert.equal('sessions' in rows[1], false)
  assert.equal(rows[2].deletions, 2)
  assert.equal('downloads' in rows[2], false)
})

test('CloudKit user counts stay unavailable when records contain no stable user ID', () => {
  const record = userId => ({ fields: userId === undefined ? {} : { userId: { value: userId } } })
  assert.equal(uniqueCloudKitUserCount([record(), record('')]), null)
  assert.equal(uniqueCloudKitUserCount([record('device-a'), record('device-a'), record('device-b')]), 2)
})
