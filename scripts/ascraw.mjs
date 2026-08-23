#!/usr/bin/env node
//
// Sawgrid — raw App Store Connect client. No dependencies, node:crypto only.
//
// As a module:
//   import { get, post, patch, del, getAll, uploadPart } from "./ascraw.mjs";
//   const app = await get("/v1/apps/6799999999");
//   const all = await getAll("/v1/territories?limit=200");
//
// As a CLI:
//   node scripts/ascraw.mjs GET    /v1/apps/6799999999
//   node scripts/ascraw.mjs GET    "/v1/apps?limit=200" --paginate
//   node scripts/ascraw.mjs POST   /v1/appStoreVersions '{"data":{...}}'
//   node scripts/ascraw.mjs PATCH  /v1/apps/6799999999 @body.json
//   node scripts/ascraw.mjs DELETE /v1/appScreenshots/abc
//
// Environment overrides:
//   ASC_KEY_ID     default 8XWLD2B2RQ
//   ASC_ISSUER_ID  default 538cb0d4-b8c6-4bc7-8b59-75da5d2b9411
//   ASC_KEY_PATH   default <noseprint>/.secrets/AuthKey_<ASC_KEY_ID>.p8
//
// ── Why this file exists next to the `asc` CLI ───────────────────────────────
// The CLI hides Apple's real error payload. Apple's top-level message is almost
// always the generic "There is a problem with the request entity"; the actual
// cause sits in errors[].meta.associatedErrors, keyed by the sub-resource that
// failed. Every failure raised here inlines those associated errors into the
// Error message, because chasing a 409 without them costs hours.

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const HOST = "https://api.appstoreconnect.apple.com";

const KEY_ID = process.env.ASC_KEY_ID || "8XWLD2B2RQ";
const ISSUER_ID = process.env.ASC_ISSUER_ID || "538cb0d4-b8c6-4bc7-8b59-75da5d2b9411";
const KEY_PATH =
  process.env.ASC_KEY_PATH ||
  `/Users/levinschwab/Data/Claude/noseprint/.secrets/AuthKey_${KEY_ID}.p8`;

// ── JWT ──────────────────────────────────────────────────────────────────────
const b64url = (input) =>
  Buffer.from(input).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

let cachedToken = null; // { jwt, exp }

function makeJWT() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - now > 60) return cachedToken.jwt;

  if (!fs.existsSync(KEY_PATH)) {
    throw new Error(
      `ASC private key not found at ${KEY_PATH}\n` +
        `  Set ASC_KEY_PATH, or place AuthKey_${KEY_ID}.p8 there.`
    );
  }

  const header = { alg: "ES256", kid: KEY_ID, typ: "JWT" };
  const exp = now + 19 * 60; // Apple rejects anything over 20 minutes
  const payload = { iss: ISSUER_ID, iat: now, exp, aud: "appstoreconnect-v1" };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;

  const sign = crypto.createSign("SHA256");
  sign.update(signingInput);
  sign.end();
  // ES256 needs the raw r||s pair. The default DER encoding is silently rejected
  // by Apple as an invalid signature.
  const signature = sign.sign({ key: fs.readFileSync(KEY_PATH), dsaEncoding: "ieee-p1363" });

  const jwt = `${signingInput}.${b64url(signature)}`;
  cachedToken = { jwt, exp };
  return jwt;
}

// ── error formatting ─────────────────────────────────────────────────────────
// errors[].meta.associatedErrors is an OBJECT keyed by the resource path, whose
// values are arrays of the real errors. Older payloads sometimes hand back a
// plain array. Handle both, and never swallow either.
function flattenAssociated(meta) {
  const assoc = meta && meta.associatedErrors;
  if (!assoc) return [];
  const out = [];
  const push = (key, e) => {
    const bits = [e.code, e.title, e.detail].filter(Boolean).join(" — ");
    out.push(key ? `${key}: ${bits}` : bits);
  };
  if (Array.isArray(assoc)) {
    for (const e of assoc) push(null, e);
  } else {
    for (const [key, list] of Object.entries(assoc)) {
      for (const e of Array.isArray(list) ? list : [list]) push(key, e);
    }
  }
  return out;
}

function formatBody(body) {
  if (!body) return "(empty response body)";
  if (!Array.isArray(body.errors)) return JSON.stringify(body, null, 2);

  const lines = [];
  for (const e of body.errors) {
    const head = [e.status, e.code, e.title].filter(Boolean).join(" ");
    lines.push(`  ${head}`);
    if (e.detail) lines.push(`    detail: ${e.detail}`);
    if (e.source && e.source.pointer) lines.push(`    pointer: ${e.source.pointer}`);
    if (e.source && e.source.parameter) lines.push(`    parameter: ${e.source.parameter}`);
    const assoc = flattenAssociated(e.meta);
    if (assoc.length) {
      lines.push(`    associatedErrors (${assoc.length}) — THIS is usually the real cause:`);
      for (const a of assoc) lines.push(`      - ${a}`);
    }
  }
  return lines.join("\n");
}

export class AscError extends Error {
  constructor(status, method, pathname, body) {
    super(`ASC ${status} ${method} ${pathname}\n${formatBody(body)}`);
    this.name = "AscError";
    this.status = status;
    this.method = method;
    this.path = pathname;
    this.body = body;
    this.errors = (body && body.errors) || [];
    this.associatedErrors = this.errors.flatMap((e) => flattenAssociated(e.meta));
  }
}

// ── core request ─────────────────────────────────────────────────────────────
export async function request(method, pathname, body = undefined, opts = {}) {
  const url = pathname.startsWith("http") ? pathname : `${HOST}${pathname}`;
  const init = {
    method,
    headers: {
      Authorization: `Bearer ${makeJWT()}`,
      "Content-Type": "application/json",
      ...(opts.headers || {}),
    },
  };
  if (body !== undefined && body !== null) {
    init.body = typeof body === "string" ? body : JSON.stringify(body);
  }

  const res = await fetch(url, init);
  const text = await res.text();
  let json = null;
  if (text) {
    try {
      json = JSON.parse(text);
    } catch {
      json = { raw: text };
    }
  }
  if (!res.ok) throw new AscError(res.status, method, pathname, json);
  return json;
}

export const get = (pathname, opts) => request("GET", pathname, undefined, opts);
export const post = (pathname, body, opts) => request("POST", pathname, body, opts);
export const patch = (pathname, body, opts) => request("PATCH", pathname, body, opts);
export const del = (pathname, opts) => request("DELETE", pathname, undefined, opts);

// ── pagination ───────────────────────────────────────────────────────────────
// Follows links.next until exhausted and returns one merged payload. `included`
// is concatenated too, because relationship lookups depend on it.
export async function getAll(pathname, opts = {}) {
  const limit = opts.max ?? Infinity;
  let next = pathname;
  const data = [];
  const included = [];
  let meta = null;

  while (next && data.length < limit) {
    const page = await get(next, opts);
    if (Array.isArray(page.data)) data.push(...page.data);
    else if (page.data) data.push(page.data);
    if (Array.isArray(page.included)) included.push(...page.included);
    meta = page.meta || meta;
    next = page.links && page.links.next ? page.links.next : null;
  }

  return { data: limit === Infinity ? data : data.slice(0, limit), included, meta };
}

// Convenience: paginate and return the first element matching `pred`, or null.
// This is how price points get resolved — the wanted point is rarely on page 1.
export async function findAcross(pathname, pred, opts = {}) {
  let next = pathname;
  while (next) {
    const page = await get(next, opts);
    const hit = (page.data || []).find(pred);
    if (hit) return { hit, included: page.included || [] };
    next = page.links && page.links.next ? page.links.next : null;
  }
  return null;
}

// ── asset upload ─────────────────────────────────────────────────────────────
// Reserved-asset uploads (screenshots, app previews) go to a pre-signed URL on a
// DIFFERENT host and must NOT carry the bearer token — Apple 403s if it is sent.
export async function uploadPart(operation, chunk) {
  const headers = {};
  for (const h of operation.requestHeaders || []) headers[h.name] = h.value;
  const res = await fetch(operation.url, { method: operation.method, headers, body: chunk });
  if (!res.ok) {
    throw new Error(
      `asset upload ${res.status} ${operation.method} ${operation.url}\n${await res.text()}`
    );
  }
}

export const md5 = (buf) => crypto.createHash("md5").update(buf).digest("hex");

// ── CLI ──────────────────────────────────────────────────────────────────────
const isMain = import.meta.url === `file://${process.argv[1]}`;
if (isMain) {
  const argv = process.argv.slice(2);
  const paginate = argv.includes("--paginate");
  const rest = argv.filter((a) => a !== "--paginate");
  const [method, pathname, rawBody] = rest;

  if (!method || !pathname) {
    console.error(
      "usage: node ascraw.mjs <GET|POST|PATCH|DELETE> <path> [json|@file] [--paginate]"
    );
    process.exit(2);
  }

  let body;
  if (rawBody) {
    body = rawBody.startsWith("@")
      ? fs.readFileSync(path.resolve(rawBody.slice(1)), "utf8")
      : rawBody;
  }

  const run =
    paginate && method.toUpperCase() === "GET"
      ? getAll(pathname)
      : request(method.toUpperCase(), pathname, body);

  run
    .then((j) => console.log(JSON.stringify(j, null, 2)))
    .catch((e) => {
      console.error(e.message);
      process.exit(1);
    });
}
