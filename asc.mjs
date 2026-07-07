#!/usr/bin/env node
// App Store Connect helper: inspect TestFlight state and distribute the
// latest processed build to a beta group (assign + submit for beta review).
//
//   node asc.mjs status
//   node asc.mjs distribute "<group name>"
//
// Reads the API key from AuthKey_<KEY_ID>.p8 next to this script.

import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'

const KEY_ID = process.env.ASC_KEY_ID || '7P36JWYZ3S'
const ISSUER = process.env.ASC_ISSUER || '193ae824-6e63-491f-876f-fa75bff52dba'
const BUNDLE_ID = 'com.studio86.simply'
const API = 'https://api.appstoreconnect.apple.com/v1'

function token() {
  const header = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' }
  const now = Math.floor(Date.now() / 1000)
  const payload = { iss: ISSUER, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' }
  const b64 = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url')
  const unsigned = `${b64(header)}.${b64(payload)}`
  const key = fs.readFileSync(path.join(import.meta.dirname, `AuthKey_${KEY_ID}.p8`))
  const signature = crypto
    .sign('sha256', Buffer.from(unsigned), { key, dsaEncoding: 'ieee-p1363' })
    .toString('base64url')
  return `${unsigned}.${signature}`
}

async function api(method, endpoint, body) {
  const res = await fetch(endpoint.startsWith('http') ? endpoint : `${API}${endpoint}`, {
    method,
    headers: {
      Authorization: `Bearer ${token()}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  const json = text ? JSON.parse(text) : {}
  if (!res.ok) {
    throw new Error(`${method} ${endpoint} -> ${res.status}: ${JSON.stringify(json.errors || json).slice(0, 400)}`)
  }
  return json
}

async function appId() {
  const apps = await api('GET', `/apps?filter[bundleId]=${BUNDLE_ID}`)
  if (!apps.data?.length) throw new Error(`no app for ${BUNDLE_ID}`)
  return apps.data[0].id
}

async function builds(app) {
  const res = await api(
    'GET',
    `/builds?filter[app]=${app}&sort=-uploadedDate&limit=10` +
      '&fields[builds]=version,uploadedDate,expirationDate,expired,processingState',
  )
  return res.data
}

async function groups(app) {
  const res = await api(
    'GET',
    `/betaGroups?filter[app]=${app}&fields[betaGroups]=name,isInternalGroup,publicLinkEnabled,publicLink`,
  )
  return res.data
}

async function preReleaseVersion(buildId) {
  const res = await api('GET', `/builds/${buildId}/preReleaseVersion`)
  return res.data?.attributes?.version
}

async function betaReviewState(buildId) {
  try {
    const res = await api('GET', `/builds/${buildId}/betaAppReviewSubmission`)
    return res.data?.attributes?.betaReviewState || 'NOT_SUBMITTED'
  } catch {
    return 'NOT_SUBMITTED'
  }
}

const cmd = process.argv[2] || 'status'
const app = await appId()

if (cmd === 'status') {
  console.log('== Beta groups ==')
  for (const g of await groups(app)) {
    const a = g.attributes
    console.log(
      `- ${a.name} (${a.isInternalGroup ? 'internal' : 'external'})` +
        (a.publicLinkEnabled ? ` public link: ${a.publicLink}` : ''),
    )
  }
  console.log('== Builds (newest first) ==')
  for (const b of await builds(app)) {
    const a = b.attributes
    const marketing = await preReleaseVersion(b.id)
    const review = await betaReviewState(b.id)
    console.log(
      `- ${marketing} (${a.version})  ${a.processingState}  review:${review}` +
        `  expires:${(a.expirationDate || '').slice(0, 10)}${a.expired ? ' EXPIRED' : ''}`,
    )
  }
} else if (cmd === 'distribute') {
  const groupName = process.argv[3]
  if (!groupName) throw new Error('usage: node asc.mjs distribute "<group name>"')
  const all = await groups(app)
  const group = all.find((g) => g.attributes.name.toLowerCase() === groupName.toLowerCase())
  if (!group) throw new Error(`no group "${groupName}" — have: ${all.map((g) => g.attributes.name).join(', ')}`)

  // Newest fully processed build
  const candidates = await builds(app)
  const build = candidates.find((b) => b.attributes.processingState === 'VALID' && !b.attributes.expired)
  if (!build) throw new Error('no processed build yet — wait for App Store Connect processing and retry')
  const marketing = await preReleaseVersion(build.id)
  console.log(`latest processed build: ${marketing} (${build.attributes.version})`)

  await api('POST', `/betaGroups/${group.id}/relationships/builds`, {
    data: [{ type: 'builds', id: build.id }],
  })
  console.log(`assigned to group "${group.attributes.name}"`)

  const review = await betaReviewState(build.id)
  if (review === 'NOT_SUBMITTED') {
    try {
      await api('POST', '/betaAppReviewSubmissions', {
        data: {
          type: 'betaAppReviewSubmissions',
          relationships: { build: { data: { type: 'builds', id: build.id } } },
        },
      })
      console.log('submitted for Beta App Review')
    } catch (e) {
      console.log(`beta review submission: ${e.message}`)
    }
  } else {
    console.log(`beta review state: ${review}`)
  }
} else {
  throw new Error(`unknown command ${cmd}`)
}
