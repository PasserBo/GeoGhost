#!/usr/bin/env node
// App Store Connect steps of a release, used by scripts/release.sh.
//
//   node scripts/asc-release.mjs prepare <version> <build> <notes.json>
//     waits for the uploaded build to finish processing, creates the App Store version
//     (or reuses it), sets "What's New" per locale from notes.json, attaches the build.
//   node scripts/asc-release.mjs submit <version>
//     submits that version for review.
//   node scripts/asc-release.mjs show <version>
//     prints that version's state and store texts per locale (changes nothing).
//   node scripts/asc-release.mjs listing <version> <listing.json>
//     sets the promotional text and description per locale from listing.json
//     ({ "<locale>": { "promotionalText": "…", "description": "…" }, … }; either may be left out).
//
// Key and issuer live outside the repo: ~/.config/geoghost-release/config.json
// ({ "keyId", "issuerId", optional "keyPath" }), overridable with ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH.

import { createSign } from "node:crypto";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";

const BUNDLE_ID = "com.passerbo.geoghost";
const fileConfig = JSON.parse(readFileSync(`${homedir()}/.config/geoghost-release/config.json`, "utf8"));
const keyId = process.env.ASC_KEY_ID ?? fileConfig.keyId;
const issuerId = process.env.ASC_ISSUER_ID ?? fileConfig.issuerId;
const keyPath = process.env.ASC_KEY_PATH ?? fileConfig.keyPath ?? `${homedir()}/.appstoreconnect/private_keys/AuthKey_${keyId}.p8`;

function token() {
  const now = Math.floor(Date.now() / 1000);
  const encode = (obj) => Buffer.from(JSON.stringify(obj)).toString("base64url");
  const unsigned = `${encode({ alg: "ES256", kid: keyId, typ: "JWT" })}.${encode({
    iss: issuerId, iat: now, exp: now + 600, aud: "appstoreconnect-v1",
  })}`;
  const sig = createSign("SHA256").update(unsigned).sign({ key: readFileSync(keyPath), dsaEncoding: "ieee-p1363" });
  return `${unsigned}.${sig.toString("base64url")}`;
}

async function asc(method, path, data) {
  const res = await fetch(`https://api.appstoreconnect.apple.com/v1${path}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, "Content-Type": "application/json" },
    body: data && JSON.stringify({ data }),
  });
  const json = res.status === 204 ? {} : await res.json();
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}\n${JSON.stringify(json.errors ?? json, null, 2)}`);
  return json;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (msg) => console.log(`[asc] ${msg}`);

async function appId() {
  const id = (await asc("GET", `/apps?filter[bundleId]=${BUNDLE_ID}&fields[apps]=bundleId`)).data[0]?.id;
  if (!id) throw new Error(`No app with bundle ID ${BUNDLE_ID}`);
  return id;
}

/// A freshly uploaded build takes a while to appear in the API, then to process.
async function waitForBuild(app, version, build) {
  const deadline = Date.now() + 60 * 60 * 1000;
  for (;;) {
    const b = (await asc("GET", `/builds?filter[app]=${app}&filter[version]=${build}` +
      `&filter[preReleaseVersion.version]=${version}&fields[builds]=version,processingState`)).data[0];
    const state = b?.attributes.processingState ?? "NOT_FOUND";
    if (state === "VALID") return b;
    if (state === "FAILED" || state === "INVALID") throw new Error(`Build ${version} (${build}) is ${state}; see App Store Connect for the reason.`);
    if (Date.now() > deadline) throw new Error(`Build ${version} (${build}) still ${state} after 60 minutes.`);
    log(`build ${version} (${build}): ${state}, checking again in 30 s`);
    await sleep(30_000);
  }
}

async function findVersion(app, version) {
  const all = (await asc("GET", `/apps/${app}/appStoreVersions?filter[platform]=IOS&fields[appStoreVersions]=versionString,appStoreState`)).data;
  return all.find((v) => v.attributes.versionString === version);
}

async function prepare(version, build, notesPath) {
  const notes = JSON.parse(readFileSync(notesPath, "utf8"));
  const app = await appId();
  const b = await waitForBuild(app, version, build);
  log(`build ${version} (${build}) processed`);

  let v = await findVersion(app, version);
  if (!v) {
    v = (await asc("POST", "/appStoreVersions", {
      type: "appStoreVersions",
      attributes: { platform: "IOS", versionString: version, releaseType: "AFTER_APPROVAL" },
      relationships: { app: { data: { type: "apps", id: app } } },
    })).data;
    log(`created version ${version}`);
  } else {
    log(`version ${version} exists (${v.attributes.appStoreState})`);
  }

  // A new version copies the previous version's localizations; fill in What's New for each.
  const locs = (await asc("GET", `/appStoreVersions/${v.id}/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale`)).data;
  for (const [locale, whatsNew] of Object.entries(notes)) {
    const loc = locs.find((l) => l.attributes.locale === locale);
    if (!loc) throw new Error(`Version ${version} has no ${locale} localization; add it in App Store Connect or drop it from ${notesPath}.`);
    await asc("PATCH", `/appStoreVersionLocalizations/${loc.id}`, { type: "appStoreVersionLocalizations", id: loc.id, attributes: { whatsNew } });
    log(`What's New set for ${locale}`);
  }
  const missing = locs.map((l) => l.attributes.locale).filter((l) => !(l in notes));
  if (missing.length) throw new Error(`No What's New for ${missing.join(", ")} in ${notesPath}.`);

  await asc("PATCH", `/appStoreVersions/${v.id}/relationships/build`, { type: "builds", id: b.id });
  log(`build ${build} attached to ${version}`);
}

async function submit(version) {
  const app = await appId();
  const v = await findVersion(app, version);
  if (!v) throw new Error(`No App Store version ${version}; run prepare first.`);

  // Only one open submission per app; reuse a draft left by an earlier attempt.
  const open = (await asc("GET", `/reviewSubmissions?filter[app]=${app}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW`)).data[0];
  const sub = open ?? (await asc("POST", "/reviewSubmissions", {
    type: "reviewSubmissions",
    attributes: { platform: "IOS" },
    relationships: { app: { data: { type: "apps", id: app } } },
  })).data;

  const items = (await asc("GET", `/reviewSubmissions/${sub.id}/items?include=appStoreVersion`)).data;
  if (!items.some((i) => i.relationships?.appStoreVersion?.data?.id === v.id)) {
    await asc("POST", "/reviewSubmissionItems", {
      type: "reviewSubmissionItems",
      relationships: {
        reviewSubmission: { data: { type: "reviewSubmissions", id: sub.id } },
        appStoreVersion: { data: { type: "appStoreVersions", id: v.id } },
      },
    });
  }
  await asc("PATCH", `/reviewSubmissions/${sub.id}`, { type: "reviewSubmissions", id: sub.id, attributes: { submitted: true } });
  log(`${version} submitted for review`);
}

const TEXTS = ["promotionalText", "description", "whatsNew"];

async function localizations(version) {
  const v = await findVersion(await appId(), version);
  if (!v) throw new Error(`No App Store version ${version}.`);
  const locs = (await asc("GET", `/appStoreVersions/${v.id}/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale,${TEXTS.join(",")}`)).data;
  return { v, locs };
}

async function show(version) {
  const { v, locs } = await localizations(version);
  console.log(`${version}: ${v.attributes.appStoreState}`);
  for (const loc of locs) {
    for (const key of TEXTS) console.log(`\n=== ${loc.attributes.locale} · ${key}\n${loc.attributes[key] ?? "(empty)"}`);
  }
}

async function listing(version, path) {
  const wanted = JSON.parse(readFileSync(path, "utf8"));
  const { locs } = await localizations(version);
  for (const [locale, texts] of Object.entries(wanted)) {
    const loc = locs.find((l) => l.attributes.locale === locale);
    if (!loc) throw new Error(`Version ${version} has no ${locale} localization.`);
    const attributes = Object.fromEntries(Object.entries(texts).filter(([key]) => key === "promotionalText" || key === "description"));
    if (attributes.promotionalText?.length > 170) throw new Error(`${locale}: promotional text is ${attributes.promotionalText.length} characters (limit 170).`);
    if (attributes.description?.length > 4000) throw new Error(`${locale}: description is ${attributes.description.length} characters (limit 4000).`);
    await asc("PATCH", `/appStoreVersionLocalizations/${loc.id}`, { type: "appStoreVersionLocalizations", id: loc.id, attributes });
    log(`${Object.keys(attributes).join(" and ")} set for ${locale}`);
  }
}

const [cmd, ...args] = process.argv.slice(2);
try {
  if (cmd === "prepare" && args.length === 3) await prepare(...args);
  else if (cmd === "submit" && args.length === 1) await submit(...args);
  else if (cmd === "show" && args.length === 1) await show(...args);
  else if (cmd === "listing" && args.length === 2) await listing(...args);
  else {
    console.error("usage: asc-release.mjs prepare <version> <build> <notes.json> | submit <version> | show <version> | listing <version> <listing.json>");
    process.exit(2);
  }
} catch (e) {
  console.error(`[asc] ${e.message}`);
  process.exit(1);
}
