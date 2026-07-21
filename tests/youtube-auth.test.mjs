import assert from 'node:assert/strict'
import { mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import {
  buildAuthorizationUrl,
  exchangeAuthorizationCode,
  updateEnvValueAtomically,
  validateLoopbackRedirect,
  verifyYouTubeChannel,
  YOUTUBE_OAUTH_SCOPES,
} from '../scripts/youtube-auth.mjs'

test('OAuth URL is offline, consented, state-bound and limited to approved scopes', () => {
  const redirectUri = validateLoopbackRedirect('http://127.0.0.1:53682/oauth2callback')
  const url = new URL(buildAuthorizationUrl({
    clientId: 'client-id', redirectUri, state: 'state-value', codeChallenge: 'challenge-value',
  }))
  assert.equal(url.origin + url.pathname, 'https://accounts.google.com/o/oauth2/v2/auth')
  assert.equal(url.searchParams.get('access_type'), 'offline')
  assert.equal(url.searchParams.get('prompt'), 'consent')
  assert.equal(url.searchParams.get('state'), 'state-value')
  assert.equal(url.searchParams.get('code_challenge_method'), 'S256')
  assert.deepEqual(url.searchParams.get('scope').split(' '), [...YOUTUBE_OAUTH_SCOPES])
  assert.equal(url.searchParams.get('scope').includes('youtube.force-ssl'), false)
})

test('redirect validation accepts only fixed 127.0.0.1 callback URLs', () => {
  assert.equal(
    validateLoopbackRedirect('http://127.0.0.1:53682/oauth2callback'),
    'http://127.0.0.1:53682/oauth2callback',
  )
  assert.throws(() => validateLoopbackRedirect('http://localhost:53682/oauth2callback'), /127\.0\.0\.1/)
  assert.throws(() => validateLoopbackRedirect('https://127.0.0.1:53682/oauth2callback'), /127\.0\.0\.1/)
  assert.throws(() => validateLoopbackRedirect('http://127.0.0.1:53682/other'), /oauth2callback/)
})

test('authorization code exchange uses PKCE and never needs a force-ssl scope', async () => {
  let request
  const result = await exchangeAuthorizationCode({
    clientId: 'client', clientSecret: 'secret', redirectUri: 'http://127.0.0.1:53682/oauth2callback',
    code: 'code', codeVerifier: 'verifier',
    fetchImpl: async (url, options) => {
      request = { url, options }
      return { ok: true, status: 200, json: async () => ({ access_token: 'access', refresh_token: 'refresh' }) }
    },
  })
  assert.deepEqual(result, { accessToken: 'access', refreshToken: 'refresh' })
  assert.equal(request.url, 'https://oauth2.googleapis.com/token')
  assert.equal(request.options.body.get('code_verifier'), 'verifier')
  assert.equal(request.options.body.get('grant_type'), 'authorization_code')
})

test('channel verification fails closed before a mismatched channel token can be stored', async () => {
  const fetchImpl = async () => ({
    ok: true,
    status: 200,
    json: async () => ({ items: [{ id: 'wrong-channel', snippet: { title: 'Wrong' } }] }),
  })
  await assert.rejects(
    verifyYouTubeChannel({ accessToken: 'access', expectedChannelId: 'expected-channel', fetchImpl }),
    /kein Token gespeichert/,
  )
})

test('refresh token update is atomic, private and preserves unrelated settings', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'flaggenbande-oauth-'))
  const envPath = join(directory, '.env.platforms')
  try {
    await writeFile(envPath, 'YOUTUBE_CLIENT_ID=client\nOTHER_SETTING=kept\nYOUTUBE_REFRESH_TOKEN=old\nYOUTUBE_REFRESH_TOKEN=duplicate\n')
    await updateEnvValueAtomically(envPath, 'YOUTUBE_REFRESH_TOKEN', 'new-refresh-token')
    const content = await readFile(envPath, 'utf8')
    assert.match(content, /YOUTUBE_CLIENT_ID=client/)
    assert.match(content, /OTHER_SETTING=kept/)
    assert.equal(content.match(/^YOUTUBE_REFRESH_TOKEN=/gm)?.length, 1)
    assert.match(content, /YOUTUBE_REFRESH_TOKEN=new-refresh-token/)
    assert.equal((await stat(envPath)).mode & 0o777, 0o600)
  } finally {
    await rm(directory, { recursive: true, force: true })
  }
})
