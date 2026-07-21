import { createHash, randomBytes, timingSafeEqual } from 'node:crypto'
import { spawn } from 'node:child_process'
import { createServer } from 'node:http'
import { chmod, mkdir, readFile, rename, unlink, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const ENV_PATH = resolve(REPOSITORY_ROOT, '.env.platforms')
const DEFAULT_REDIRECT_URI = 'http://127.0.0.1:53682/oauth2callback'
const AUTHORIZATION_ENDPOINT = 'https://accounts.google.com/o/oauth2/v2/auth'
const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token'
const AUTH_TIMEOUT_MS = 5 * 60 * 1000
const REQUEST_TIMEOUT_MS = 30 * 1000

export const YOUTUBE_OAUTH_SCOPES = Object.freeze([
  'https://www.googleapis.com/auth/youtube.upload',
  'https://www.googleapis.com/auth/youtube.readonly',
  'https://www.googleapis.com/auth/yt-analytics.readonly',
])

const errorMessage = error => error instanceof Error ? error.message : String(error)

const requiredEnv = name => {
  const value = process.env[name]?.trim()
  if (!value) throw new Error(`${name} fehlt in der lokalen .env.platforms.`)
  return value
}

export function validateLoopbackRedirect(value) {
  let redirect
  try {
    redirect = new URL(value)
  } catch {
    throw new Error('YOUTUBE_REDIRECT_URI ist keine gültige URL.')
  }
  const port = Number(redirect.port)
  if (redirect.protocol !== 'http:' || redirect.hostname !== '127.0.0.1' ||
      !Number.isInteger(port) || port < 1024 || port > 65535 ||
      redirect.pathname !== '/oauth2callback' || redirect.username || redirect.password ||
      redirect.search || redirect.hash) {
    throw new Error('YOUTUBE_REDIRECT_URI muss exakt eine lokale 127.0.0.1-Loopback-URL mit festem Port und /oauth2callback sein.')
  }
  return redirect.toString()
}

export function buildAuthorizationUrl({ clientId, redirectUri, state, codeChallenge }) {
  const url = new URL(AUTHORIZATION_ENDPOINT)
  url.search = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: 'code',
    access_type: 'offline',
    prompt: 'consent',
    include_granted_scopes: 'true',
    scope: YOUTUBE_OAUTH_SCOPES.join(' '),
    state,
    code_challenge: codeChallenge,
    code_challenge_method: 'S256',
  }).toString()
  return url.toString()
}

const stateMatches = (actual, expected) => {
  if (typeof actual !== 'string' || actual.length !== expected.length) return false
  return timingSafeEqual(Buffer.from(actual), Buffer.from(expected))
}

const openInBrowser = (url, onError) => {
  const browser = spawn('open', [url], { detached: true, stdio: 'ignore' })
  browser.once('error', () => onError(new Error('Der Standardbrowser konnte nicht sicher geöffnet werden. OAuth wurde abgebrochen.')))
  browser.unref()
}

export async function waitForAuthorizationCode({ redirectUri, expectedState, authorizationUrl, timeoutMs = AUTH_TIMEOUT_MS }) {
  const redirect = new URL(redirectUri)
  return await new Promise((resolvePromise, reject) => {
    let settled = false
    let timeout
    const server = createServer((request, response) => {
      const requestUrl = new URL(request.url ?? '/', redirectUri)
      if (request.method !== 'GET' || requestUrl.pathname !== redirect.pathname) {
        response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' }).end('Not found')
        return
      }
      const oauthError = requestUrl.searchParams.get('error')
      const state = requestUrl.searchParams.get('state')
      const code = requestUrl.searchParams.get('code')
      if (oauthError) {
        response.writeHead(400, { 'content-type': 'text/plain; charset=utf-8' })
          .end('YouTube authorization was cancelled. You can close this tab.')
        finish(new Error(`Google-OAuth wurde abgelehnt: ${oauthError}`))
        return
      }
      if (!stateMatches(state, expectedState) || !code) {
        response.writeHead(400, { 'content-type': 'text/plain; charset=utf-8' })
          .end('Invalid OAuth callback. You can close this tab.')
        finish(new Error('Ungültiger OAuth-Rückruf oder CSRF-State.'))
        return
      }
      response.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' })
        .end('Flaggenbande is connected to YouTube. You can close this tab.')
      finish(null, code)
    })

    const finish = (error, code) => {
      if (settled) return
      settled = true
      if (timeout) clearTimeout(timeout)
      server.close(() => {
        if (error) reject(error)
        else resolvePromise(code)
      })
    }

    server.once('error', error => finish(error))
    server.listen(Number(redirect.port), redirect.hostname, () => {
      timeout = setTimeout(
        () => finish(new Error('Google-OAuth-Rückruf hat nach fünf Minuten das Zeitlimit überschritten.')),
        timeoutMs,
      )
      if (process.env.YOUTUBE_OAUTH_MANUAL === 'true') {
        console.log(`Google-OAuth-URL: ${authorizationUrl}`)
      } else {
        openInBrowser(authorizationUrl, error => finish(error))
      }
    })
  })
}

async function responseJson(response) {
  return await response.json().catch(() => ({}))
}

export async function exchangeAuthorizationCode({ clientId, clientSecret, redirectUri, code, codeVerifier, fetchImpl = fetch }) {
  const response = await fetchImpl(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: redirectUri,
      grant_type: 'authorization_code',
      code,
      code_verifier: codeVerifier,
    }),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  })
  const body = await responseJson(response)
  if (!response.ok || typeof body.access_token !== 'string') {
    throw new Error(`Google konnte den OAuth-Code nicht austauschen (HTTP ${response.status}).`)
  }
  if (typeof body.refresh_token !== 'string' || !body.refresh_token.trim()) {
    throw new Error('Google lieferte keinen Refresh-Token. Den Kontozugriff widerrufen und die Zustimmung erneut ausführen.')
  }
  return { accessToken: body.access_token, refreshToken: body.refresh_token }
}

export async function verifyYouTubeChannel({ accessToken, expectedChannelId, fetchImpl = fetch }) {
  const response = await fetchImpl('https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true&maxResults=1', {
    headers: { authorization: `Bearer ${accessToken}` },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  })
  const body = await responseJson(response)
  const channel = body.items?.[0]
  if (!response.ok || typeof channel?.id !== 'string') {
    throw new Error(`Der verbundene YouTube-Kanal konnte nicht geprüft werden (HTTP ${response.status}).`)
  }
  if (channel.id !== expectedChannelId) {
    throw new Error('Das gewählte Google-Konto gehört nicht zum konfigurierten Flaggenbande-YouTube-Kanal. Es wurde kein Token gespeichert.')
  }
  return { id: channel.id, title: channel.snippet?.title ?? 'Flaggenbande' }
}

export async function updateEnvValueAtomically(envPath, name, value) {
  if (!/^[A-Z][A-Z0-9_]*$/.test(name)) throw new Error('Ungültiger ENV-Name.')
  if (typeof value !== 'string' || !value || /[\r\n\0]/.test(value)) throw new Error(`Ungültiger Wert für ${name}.`)
  let source = ''
  try {
    source = await readFile(envPath, 'utf8')
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error
  }
  const matcher = new RegExp(`^\\s*(?:export\\s+)?${name}\\s*=.*$`)
  const lines = source.split(/\r?\n/)
  const output = []
  let written = false
  for (const line of lines) {
    if (!matcher.test(line)) {
      output.push(line)
      continue
    }
    if (!written) output.push(`${name}=${value}`)
    written = true
  }
  if (!written) {
    if (output.length > 0 && output.at(-1) !== '') output.push('')
    output.push(`${name}=${value}`)
  }
  while (output.length > 1 && output.at(-1) === '' && output.at(-2) === '') output.pop()
  const serialized = `${output.join('\n').replace(/^\n+/, '')}\n`
  await mkdir(dirname(envPath), { recursive: true })
  const temporaryPath = `${envPath}.tmp-${process.pid}-${Date.now()}`
  try {
    await writeFile(temporaryPath, serialized, { encoding: 'utf8', mode: 0o600, flag: 'wx' })
    await rename(temporaryPath, envPath)
    await chmod(envPath, 0o600)
  } catch (error) {
    await unlink(temporaryPath).catch(() => undefined)
    throw error
  }
}

async function main() {
  const clientId = requiredEnv('YOUTUBE_CLIENT_ID')
  const clientSecret = requiredEnv('YOUTUBE_CLIENT_SECRET')
  const expectedChannelId = requiredEnv('YOUTUBE_CHANNEL_ID')
  const redirectUri = validateLoopbackRedirect(process.env.YOUTUBE_REDIRECT_URI?.trim() || DEFAULT_REDIRECT_URI)
  const state = randomBytes(32).toString('hex')
  const codeVerifier = randomBytes(48).toString('base64url')
  const codeChallenge = createHash('sha256').update(codeVerifier).digest('base64url')
  const authorizationUrl = buildAuthorizationUrl({ clientId, redirectUri, state, codeChallenge })

  console.log('Öffne die offizielle Google-Anmeldung für den Flaggenbande-YouTube-Kanal …')
  const code = await waitForAuthorizationCode({ redirectUri, expectedState: state, authorizationUrl })
  console.log('Google-Zustimmung empfangen. Prüfe jetzt den verbundenen YouTube-Kanal …')
  const tokens = await exchangeAuthorizationCode({ clientId, clientSecret, redirectUri, code, codeVerifier })
  const channel = await verifyYouTubeChannel({ accessToken: tokens.accessToken, expectedChannelId })
  await updateEnvValueAtomically(ENV_PATH, 'YOUTUBE_REFRESH_TOKEN', tokens.refreshToken)
  console.log(`YouTube-OAuth erfolgreich für „${channel.title}“.`)
  console.log('Der Refresh-Token wurde sicher in der lokalen .env.platforms gespeichert. Es wurde kein Video hochgeladen.')
}

const directInvocation = typeof process !== 'undefined' &&
  process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (directInvocation) {
  main().catch(error => {
    console.error(`YouTube-OAuth fehlgeschlagen: ${errorMessage(error)}`)
    process.exitCode = 1
  })
}
