#!/usr/bin/env node
// App Store submission helper, built on the same API key as asc.mjs.
// Steps, in order:
//
//   node asc-submit.mjs probe          - show current state
//   node asc-submit.mjs prepare        - version string/manual release, metadata, categories, age rating
//   node asc-submit.mjs screenshots    - upload the Desktop 6.9" screenshot set
//   node asc-submit.mjs attach-build 39
//   node asc-submit.mjs review-info    - App Review contact + honest notes
//   node asc-submit.mjs price          - free, US availability
//   node asc-submit.mjs submit         - final: create + submit the review submission

import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'

const KEY_ID = process.env.ASC_KEY_ID || '7P36JWYZ3S'
const ISSUER = process.env.ASC_ISSUER || '193ae824-6e63-491f-876f-fa75bff52dba'
const BUNDLE_ID = 'com.studio86.simply'
const API = 'https://api.appstoreconnect.apple.com/v1'
const VERSION = '1.9'
const SCREENSHOT_DIR = path.join(process.env.HOME, 'Desktop', 'SimplyPure-AppStore-Screenshots')

const SUBTITLE = 'Scan food. Get honest scores.'
const PRIVACY_URL = 'https://simplypure.studio86.dev/privacy.html'
const SUPPORT_URL = 'https://simplypure.studio86.dev'
const PROMO = 'Scan any US product barcode and get one honest 0 to 100 score in '
  + 'seconds. Food, personal care, pet food, and household, scored by strict '
  + 'EU safety standards.'
const KEYWORDS = 'food scanner,barcode,additives,ingredients,nutrition,e numbers,score,healthy,label,scan,dyes,recall'
const DESCRIPTION = `Simply Pure reads the label so you don't have to. Point your camera at any barcode and get one honest score, 0 to 100, in seconds.

Most US food apps grade on nutrition alone. Simply Pure also asks a harder question: would this ingredient list be allowed in Europe? The EU reviews additives before they reach shelves and re-reviews them as evidence accumulates, so its standards are the strictest widely used benchmark in the world. We score every product against them.

WHAT YOU GET
- One score from three parts: nutrition, additive safety, and processing level, with the full breakdown shown for every product
- Hard caps that cannot be bought back: a high-risk additive caps any score at 49, an EU-banned additive caps it at 24
- Additive details in plain language: what it is, why it is or is not a concern, its status in the EU, Japan, and Canada, and an estimated dose against the accepted daily intake where the data allows
- Better options from the same aisle when they exist
- Personal care, pet food, and household products, scored on ingredient safety against EU rules
- Alerts if a product you scanned is recalled by the US FDA or its score changes after a data or safety-rules update (optional)
- Personalization for your diet and allergen list, clearly bounded so it never invents a verdict
- Themes, offline scanning of previously seen products, and sync between your devices with a short code, no account needed

INDEPENDENT BY DESIGN
No ads. No sponsored scores. No accounts. Your scan history stays on your device. The scoring method is published in full on our website, and product corrections are reviewed by a human before they go live.

If a product is missing, add it in about 30 seconds with two photos, or get an instant provisional score from a photo of the ingredient label.

Simply Pure rates products, not diets, and is not medical advice.`

const REVIEW_NOTES = `Simply Pure scans US retail barcodes and shows an ingredient-safety score computed on the device from public data (Open Food Facts and our own reviewed database). No account is needed and nothing requires sign in. To test without physical products, tap "Scan a product", then "Enter a barcode instead", and use any of these UPCs: 016000275270 (cereal), 049000042566 (soda), 737628064502 (noodle kit), 011110038364 (soup mix).

Every feature in the app is available to every user without payment. The profile contains an optional "Support Simply Pure" button that opens our website in the external browser (US storefront), where a user can make a voluntary annual contribution processed by Stripe. The website then shows a supporter code the user may enter in the profile; today that code changes nothing functional in the app. In a future version it will unlock optional extras such as visual themes. The profile also lets a supporter cancel that website subscription. No payment UI exists inside the app and no payment information is ever collected in the app.

The scoring methodology is published at https://simplypure.studio86.dev/methodology.html. Recall alerts and community questions are opt-in and off by default.`

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
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  const json = text ? JSON.parse(text) : {}
  if (!res.ok) {
    throw new Error(`${method} ${endpoint} -> ${res.status}: ${JSON.stringify(json.errors || json).slice(0, 600)}`)
  }
  return json
}

async function appId() {
  const apps = await api('GET', `/apps?filter[bundleId]=${BUNDLE_ID}`)
  if (!apps.data?.length) throw new Error(`no app for ${BUNDLE_ID}`)
  return apps.data[0].id
}

async function editableVersion(app) {
  const versions = await api('GET',
    `/apps/${app}/appStoreVersions?limit=5&fields[appStoreVersions]=versionString,appStoreState,releaseType`)
  const editable = versions.data.find((v) =>
    ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED']
      .includes(v.attributes.appStoreState))
  if (!editable) throw new Error('no editable App Store version found')
  return editable
}

const app = await appId()
const cmd = process.argv[2] || 'probe'

if (cmd === 'probe') {
  const versions = await api('GET',
    `/apps/${app}/appStoreVersions?limit=5&fields[appStoreVersions]=versionString,appStoreState,releaseType`)
  for (const v of versions.data) {
    console.log(`version ${v.attributes.versionString} ${v.attributes.appStoreState} release:${v.attributes.releaseType}`)
  }
} else if (cmd === 'prepare') {
  const version = await editableVersion(app)
  await api('PATCH', `/appStoreVersions/${version.id}`, {
    data: {
      type: 'appStoreVersions', id: version.id,
      attributes: { versionString: VERSION, releaseType: 'MANUAL' },
    },
  })
  console.log(`version -> ${VERSION}, manual release`)

  // en-US version localization: description, keywords, promo, URLs.
  const locs = await api('GET', `/appStoreVersions/${version.id}/appStoreVersionLocalizations`)
  let loc = locs.data.find((l) => l.attributes.locale === 'en-US')
  if (!loc) {
    loc = (await api('POST', '/appStoreVersionLocalizations', {
      data: {
        type: 'appStoreVersionLocalizations',
        attributes: { locale: 'en-US' },
        relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } },
      },
    })).data
  }
  await api('PATCH', `/appStoreVersionLocalizations/${loc.id}`, {
    data: {
      type: 'appStoreVersionLocalizations', id: loc.id,
      attributes: {
        description: DESCRIPTION,
        keywords: KEYWORDS,
        promotionalText: PROMO,
        supportUrl: SUPPORT_URL,
        marketingUrl: SUPPORT_URL,
      },
    },
  })
  console.log('localization: description, keywords, promo, urls set')

  // App info: categories per the package (primary Food & Drink), and the
  // localization's subtitle + privacy policy URL.
  const infos = await api('GET', `/apps/${app}/appInfos`)
  const info = infos.data.find((i) =>
    ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED'].includes(
      i.attributes?.appStoreState || i.attributes?.state)) || infos.data[0]
  await api('PATCH', `/appInfos/${info.id}`, {
    data: {
      type: 'appInfos', id: info.id,
      relationships: {
        primaryCategory: { data: { type: 'appCategories', id: 'FOOD_AND_DRINK' } },
        secondaryCategory: { data: { type: 'appCategories', id: 'HEALTH_AND_FITNESS' } },
      },
    },
  })
  console.log('categories: Food & Drink primary, Health & Fitness secondary')
  const infoLocs = await api('GET', `/appInfos/${info.id}/appInfoLocalizations`)
  const infoLoc = infoLocs.data.find((l) => l.attributes.locale === 'en-US')
  await api('PATCH', `/appInfoLocalizations/${infoLoc.id}`, {
    data: {
      type: 'appInfoLocalizations', id: infoLoc.id,
      attributes: { subtitle: SUBTITLE, privacyPolicyUrl: PRIVACY_URL },
    },
  })
  console.log('subtitle + privacy policy url set')

  // Age rating: everything none/false. Read the declaration and answer
  // every enum NONE and every boolean false, leaving special fields alone.
  // Lives on the appInfo in the current API (was on the version once).
  const decl = await api('GET', `/appInfos/${info.id}/ageRatingDeclaration`)
  const attrs = {}
  for (const [key, value] of Object.entries(decl.data.attributes || {})) {
    if (key === 'kidsAgeBand' || key === 'ageRatingOverride'
      || key === 'koreaAgeRatingOverride') continue
    if (typeof value === 'boolean' || value === null) {
      // Booleans (gambling, lootBox, ...) answer false; enum fields also
      // arrive as null before first save, so probe by name.
      attrs[key] = /gambling$|lootBox|unrestrictedWebAccess/.test(key) ? false : 'NONE'
      if (key === 'gambling' || key === 'lootBox' || key === 'unrestrictedWebAccess') attrs[key] = false
    } else if (typeof value === 'string') {
      attrs[key] = 'NONE'
    }
  }
  // Booleans that must be booleans regardless of the probe above.
  for (const b of ['gambling', 'lootBox', 'unrestrictedWebAccess']) {
    if (b in attrs) attrs[b] = false
  }
  await api('PATCH', `/ageRatingDeclarations/${decl.data.id}`, {
    data: { type: 'ageRatingDeclarations', id: decl.data.id, attributes: attrs },
  })
  console.log('age rating: all none ->', Object.keys(attrs).length, 'fields')
} else if (cmd === 'screenshots') {
  const version = await editableVersion(app)
  const locs = await api('GET', `/appStoreVersions/${version.id}/appStoreVersionLocalizations`)
  const loc = locs.data.find((l) => l.attributes.locale === 'en-US')
  const sets = await api('GET', `/appStoreVersionLocalizations/${loc.id}/appScreenshotSets`)
  let set = sets.data.find((s) => s.attributes.screenshotDisplayType === 'APP_IPHONE_67')
  if (!set) {
    set = (await api('POST', '/appScreenshotSets', {
      data: {
        type: 'appScreenshotSets',
        attributes: { screenshotDisplayType: 'APP_IPHONE_67' },
        relationships: {
          appStoreVersionLocalization: {
            data: { type: 'appStoreVersionLocalizations', id: loc.id },
          },
        },
      },
    })).data
  }
  const existing = await api('GET', `/appScreenshotSets/${set.id}/appScreenshots`)
  if (existing.data.length) {
    console.log(`set already has ${existing.data.length} screenshots; leaving as is`)
    process.exit(0)
  }
  const files = fs.readdirSync(SCREENSHOT_DIR).filter((f) => f.endsWith('.png')).sort()
  for (const file of files) {
    const filePath = path.join(SCREENSHOT_DIR, file)
    const bytes = fs.readFileSync(filePath)
    const shot = (await api('POST', '/appScreenshots', {
      data: {
        type: 'appScreenshots',
        attributes: { fileName: file, fileSize: bytes.length },
        relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.id } } },
      },
    })).data
    for (const op of shot.attributes.uploadOperations) {
      const headers = {}
      for (const h of op.requestHeaders || []) headers[h.name] = h.value
      const part = bytes.subarray(op.offset, op.offset + op.length)
      const res = await fetch(op.url, { method: op.method, headers, body: part })
      if (!res.ok) throw new Error(`upload part failed ${res.status} for ${file}`)
    }
    const md5 = crypto.createHash('md5').update(bytes).digest('hex')
    await api('PATCH', `/appScreenshots/${shot.id}`, {
      data: {
        type: 'appScreenshots', id: shot.id,
        attributes: { uploaded: true, sourceFileChecksum: md5 },
      },
    })
    console.log(`uploaded ${file} (${bytes.length} bytes)`)
  }
} else if (cmd === 'attach-build') {
  const number = process.argv[3]
  if (!number) throw new Error('usage: attach-build <build number>')
  const builds = await api('GET',
    `/builds?filter[app]=${app}&filter[version]=${number}&fields[builds]=version,processingState`)
  const build = builds.data.find((b) => b.attributes.processingState === 'VALID')
  if (!build) throw new Error(`build ${number} not found/processed`)
  // Standard-encryption exemption, so no compliance questions block
  // release; tolerate it already being set on the build.
  try {
    await api('PATCH', `/builds/${build.id}`, {
      data: { type: 'builds', id: build.id, attributes: { usesNonExemptEncryption: false } },
    })
  } catch (e) {
    if (!String(e.message).includes('already set')) throw e
    console.log('encryption flag already set on build')
  }
  const version = await editableVersion(app)
  await api('PATCH', `/appStoreVersions/${version.id}/relationships/build`, {
    data: { type: 'builds', id: build.id },
  })
  console.log(`build ${number} attached, encryption exempt`)
} else if (cmd === 'review-info') {
  const version = await editableVersion(app)
  const beta = await api('GET', `/apps/${app}/betaAppReviewDetail`)
  const b = beta.data.attributes
  let detail
  try {
    detail = (await api('GET', `/appStoreVersions/${version.id}/appStoreReviewDetail`)).data
  } catch {}
  const attributes = {
    contactFirstName: b.contactFirstName,
    contactLastName: b.contactLastName,
    contactEmail: b.contactEmail,
    contactPhone: b.contactPhone,
    demoAccountRequired: false,
    notes: REVIEW_NOTES,
  }
  if (detail) {
    await api('PATCH', `/appStoreReviewDetails/${detail.id}`, {
      data: { type: 'appStoreReviewDetails', id: detail.id, attributes },
    })
  } else {
    await api('POST', '/appStoreReviewDetails', {
      data: {
        type: 'appStoreReviewDetails',
        attributes,
        relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } },
      },
    })
  }
  console.log(`review contact ${b.contactFirstName} ${b.contactLastName}, honest notes set`)
} else if (cmd === 'price') {
  // Free price point for the US, base territory USA.
  const points = await api('GET',
    `/apps/${app}/appPricePoints?filter[territory]=USA&limit=1&fields[appPricePoints]=customerPrice`)
  const free = points.data.find((p) => Number(p.attributes.customerPrice) === 0)
  if (!free) throw new Error('no free price point on first page — investigate')
  try {
    await api('POST', '/appPriceSchedules', {
      data: {
        type: 'appPriceSchedules',
        relationships: {
          app: { data: { type: 'apps', id: app } },
          baseTerritory: { data: { type: 'territories', id: 'USA' } },
          manualPrices: { data: [{ type: 'appPrices', id: '${price1}' }] },
        },
      },
      included: [{
        type: 'appPrices',
        id: '${price1}',
        attributes: { startDate: null },
        relationships: { appPricePoint: { data: { type: 'appPricePoints', id: free.id } } },
      }],
    })
    console.log('price: free (USA base)')
  } catch (e) {
    console.log('price schedule:', e.message.slice(0, 120))
  }
  // The availability endpoint wants an explicit yes/no for every
  // territory: USA on, everything else off.
  const territories = []
  let url = '/territories?limit=200'
  while (url) {
    const page = await api('GET', url)
    territories.push(...page.data.map((t) => t.id))
    url = page.links?.next || null
  }
  const rel = []
  const included = []
  territories.forEach((territory, i) => {
    const placeholder = '${t' + i + '}'
    rel.push({ type: 'territoryAvailabilities', id: placeholder })
    included.push({
      type: 'territoryAvailabilities',
      id: placeholder,
      attributes: { available: territory === 'USA' },
      relationships: { territory: { data: { type: 'territories', id: territory } } },
    })
  })
  await api('POST', 'https://api.appstoreconnect.apple.com/v2/appAvailabilities', {
    data: {
      type: 'appAvailabilities',
      attributes: { availableInNewTerritories: false },
      relationships: {
        app: { data: { type: 'apps', id: app } },
        territoryAvailabilities: { data: rel },
      },
    },
    included,
  })
  console.log(`availability: United States only (of ${territories.length} territories)`)
} else if (cmd === 'submit') {
  const version = await editableVersion(app)
  let submission
  const open = await api('GET',
    `/reviewSubmissions?filter[app]=${app}&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES`)
  submission = open.data?.[0]
  if (!submission) {
    submission = (await api('POST', '/reviewSubmissions', {
      data: {
        type: 'reviewSubmissions',
        attributes: { platform: 'IOS' },
        relationships: { app: { data: { type: 'apps', id: app } } },
      },
    })).data
    console.log('review submission created')
  }
  const items = await api('GET', `/reviewSubmissions/${submission.id}/items`)
  if (!items.data.length) {
    await api('POST', '/reviewSubmissionItems', {
      data: {
        type: 'reviewSubmissionItems',
        relationships: {
          reviewSubmission: { data: { type: 'reviewSubmissions', id: submission.id } },
          appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } },
        },
      },
    })
    console.log('version added to submission')
  }
  await api('PATCH', `/reviewSubmissions/${submission.id}`, {
    data: {
      type: 'reviewSubmissions', id: submission.id,
      attributes: { submitted: true },
    },
  })
  console.log('SUBMITTED for App Review')
} else {
  throw new Error(`unknown command ${cmd}`)
}
