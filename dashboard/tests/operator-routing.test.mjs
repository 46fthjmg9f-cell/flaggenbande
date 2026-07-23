import assert from 'node:assert/strict'
import test from 'node:test'
import { operatorDashboardRedirect } from '../src/operatorRouting.ts'

const githubPagesLocation = {
  hostname: '46fthjmg9f-cell.github.io',
  origin: 'https://46fthjmg9f-cell.github.io',
  search: '?view=production',
  hash: '#draft',
}

test('GitHub Pages redirects controls to the same-origin protected Worker dashboard', () => {
  assert.equal(
    operatorDashboardRedirect(
      githubPagesLocation,
      'https://flaggenbande-operator-api.dervongesternabend123.workers.dev',
    ),
    'https://flaggenbande-operator-api.dervongesternabend123.workers.dev/?view=production#draft',
  )
})

test('Worker and local dashboards stay on their current origin', () => {
  assert.equal(
    operatorDashboardRedirect(
      {
        hostname: 'flaggenbande-operator-api.dervongesternabend123.workers.dev',
        origin: 'https://flaggenbande-operator-api.dervongesternabend123.workers.dev',
        search: '',
        hash: '',
      },
      'https://flaggenbande-operator-api.dervongesternabend123.workers.dev',
    ),
    null,
  )
  assert.equal(
    operatorDashboardRedirect(
      {
        hostname: '127.0.0.1',
        origin: 'http://127.0.0.1:4317',
        search: '',
        hash: '',
      },
      'https://flaggenbande-operator-api.dervongesternabend123.workers.dev',
    ),
    null,
  )
})

test('missing, invalid or insecure operator URLs never redirect', () => {
  assert.equal(operatorDashboardRedirect(githubPagesLocation, undefined), null)
  assert.equal(operatorDashboardRedirect(githubPagesLocation, 'not-a-url'), null)
  assert.equal(operatorDashboardRedirect(githubPagesLocation, 'http://example.test'), null)
})
