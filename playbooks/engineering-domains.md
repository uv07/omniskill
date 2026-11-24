# Engineering Domains Playbook

API/interface design, architecture, error handling, security, performance, frontend/UI, accessibility, observability, data/deploy safety, plus the **Domain Routing Catalog** (every language/framework/domain skill in the library).

How to use: read the section for the domain you are touching and run its checklist. For anything stack-specific (Django, Spring, Swift, Postgres, Terraform, video, finance...) jump to the catalog (section 10), then Read the original at `library/<path>/SKILL_SOURCE.md`.

Sibling playbooks: `planning.md` (specs, plans, ADR timing) · `tdd-testing.md` (tests, E2E, verification) · `debugging.md` (root cause, incidents) · `review-quality.md` (review, simplification) · `git-shipping.md` (commits, CI/CD, launch, rollback) · `agents-context.md` (subagents, harnesses, context, skills).

Conflict rule used throughout: when sources disagree, the **stronger** practice wins and is noted.

---

## 1. API & Interface Design

Applies to REST/GraphQL endpoints, module boundaries, component props, CLI flags, event schemas: any surface one piece of code calls.

**Core laws**
- **Hyrum's Law**: every observable behavior (error text, ordering, timing, quirks) becomes a contract. Expose intentionally; don't leak implementation; plan deprecation at design time.
- **One-Version Rule**: don't make consumers pick between versions; extend, don't fork. Multiple live versions multiply maintenance and cause diamond dependencies.
- **Contract first**: write the typed interface (inputs, outputs, errors, invariants) before the implementation. The types ARE the documentation; commit them with the code (OpenAPI/schema updated).
- **Addition over modification**: new fields optional; never change a field's type or remove it in place.
- **Validate at boundaries only**: route handlers, form handlers, env/config loading, and **third-party responses (always untrusted)**. Do not re-validate between internal functions sharing a type contract or on your own DB rows.

**REST conventions**
- URLs: plural nouns, lowercase, kebab-case (`/api/v1/team-members`), no verbs (`/getUsers` is wrong). Sub-resources for ownership (`/users/:id/orders`). Non-CRUD actions sparingly as `POST /orders/:id/cancel`.
- Methods: GET (safe, idempotent) · POST create/action (not idempotent) · PUT full replace (idempotent) · PATCH partial (prefer for updates; clients want it) · DELETE (idempotent; succeeds if already gone).
- Status codes: 200 read/update · 201 + `Location` on create · 204 no body · 400 malformed/unparseable · 401 unauthenticated · 403 authenticated-but-forbidden · 404 · 409 conflict/duplicate/version · 422 well-formed but semantically invalid · 429 + `Retry-After` · 500 (never expose internals) · 502 upstream failed · 503 + `Retry-After`. Never `200 {success:false}`; never 500 for validation.
- One error envelope everywhere: `{ "error": { "code": "VALIDATION_ERROR", "message": "...", "details": [{field, message, code}] } }`. Machine code + human message. Don't mix throw / null / `{error}` styles across endpoints.
- Response shape: envelope `{data, meta, links}` for public APIs; flat for internal is acceptable if consistent. An endpoint never returns different shapes by condition.
- Naming: match the existing API first. Default for new JSON: camelCase fields, `is/has/can` booleans, UPPER_SNAKE enum values; query params consistent with fields.
- Pagination on every list endpoint from day one, with a limit and a **stable order**. Cursor (opaque, fetch limit+1 for `has_next`) for feeds, large or public datasets; offset for admin/small (<10K) and page-numbered search. Public APIs: cursor default, offset optional.
- Filtering via query params (`?status=active`, `price[gte]=10`, comma lists, dot paths); sort `?sort=-created_at,price`; search `?q=`; sparse fields `?fields=id,name`.
- Auth: `Authorization: Bearer` for users, scoped API keys for server-to-server. Every endpoint authenticated or explicitly marked public; resource-level ownership check plus role check (see 4).
- Rate limit headers `X-RateLimit-Limit/Remaining/Reset`; tiers by anon IP / user / API key / internal service.
- Versioning: start `/api/v1/`; URL versioning preferred (explicit, cacheable). Max 2 live versions. Non-breaking (new optional fields/params/endpoints) needs no version; breaking (remove/rename/retype field, URL or auth change) does. Deprecate with notice (6 months public), `Sunset` header, then `410 Gone`. Deprecation mechanics: `git-shipping.md` + `library/addyosmani/deprecation-and-migration`.

**Idempotency (state-changing endpoints)** — accepting `Idempotency-Key` is the contract; honoring it is the implementation:
- Key derives from the **intent**, not the attempt: client-supplied header or `charge:v1:${orderId}`. Never `randomUUID()` per attempt, `${userId}:${amount}` (collapses legit duplicates), or timestamps.
- Claim atomically: INSERT with a unique constraint and catch the violation. SELECT-then-INSERT is a TOCTOU race. A store that cannot enforce uniqueness in one op cannot back this.
- Store a request hash; same key + different body → `422 IDEMPOTENCY_KEY_REUSED`.
- Choose in-flight duplicate behavior deliberately: `409` (simplest), bounded wait, or `202` + status URL. Never let a second caller through because the first "seems stuck".
- Three outcomes: success, failure, **unknown** (timeout). Record intent before calling out.
- Retention ≥ longest re-delivery path (DLQ replay, provider dispute window).
- No queue is exactly-once across consumer crashes: design at-least-once + idempotent processing. Duplicates are correlated with degraded dependencies.

**Type-level patterns**: discriminated unions for variants; separate Input vs Output types (server fields only on output); branded ID types (`TaskId` vs `UserId`); composition over configuration for component props; `PaginatedResult<T>`.

**Contract-first across teams**: one authoritative machine-readable contract (OpenAPI/JSON Schema/proto) shared by frontend/backend or service pairs → `ecc/contract-first`. New third-party connector matching repo conventions → `ecc/api-connector-builder`.

**API checklist**
- [ ] Typed input + output schema per endpoint; schema validator (Zod/Pydantic/Bean Validation) at the boundary
- [ ] Single error format; correct status codes; no stack traces/SQL in responses
- [ ] Lists paginated with stable order; filters/sort consistent
- [ ] AuthN required or explicitly public; authZ checks resource ownership/role
- [ ] Rate limiting (shared store) configured
- [ ] New fields additive/optional; naming consistent with existing endpoints
- [ ] Mutations honor an idempotency key (atomic claim, payload guard, deliberate in-flight policy, retention ≥ retry path) or are documented unsafe to retry
- [ ] Docs/OpenAPI/types committed with the implementation

Red flags: verbs in URLs; shape varies by condition; unpaginated list; scattered validation; breaking field change; third-party data used unvalidated; idempotency key from UUID/timestamp; key reused with different body silently replays.

Source detail: `addyosmani/api-and-interface-design`, `ecc/api-design`, `ecc/backend-patterns`, `ecc/contract-first`, `ecc/api-connector-builder`.

---

## 2. Architecture & Modularity

**Vocabulary (use exactly; avoid "component/service/boundary" drift)**
- **Module**: anything with an interface + implementation (function → tier-spanning slice).
- **Interface**: everything a caller must know: types **plus** invariants, ordering, error modes, config, performance.
- **Depth**: behavior per unit of interface learned. **Deep** = small interface, lots behind it. **Shallow** = interface ≈ implementation (avoid).
- **Seam**: where behavior can change without editing in place; where the interface lives. **Adapter**: the concrete thing filling a seam.
- **Leverage** (callers get more per interface learned) and **Locality** (change/bugs/knowledge concentrate in one place).

**Principles**
- **Deletion test**: delete the module in your head. Complexity vanishes → it was a pass-through. Complexity reappears across N callers → it earns its keep.
- **The interface is the test surface**. Wanting to test *past* the interface means the module is the wrong shape. Tests survive internal refactors.
- **One adapter = hypothetical seam; two adapters (e.g. prod + test) = real seam.** Don't add a port with only one implementation.
- Internal seams (private, for the module's own tests) are fine; don't expose them through the interface.
- Testability: accept dependencies (don't `new` them inside); return results rather than mutate; small surface.
- Ask of every interface: fewer methods? simpler params? hide more inside?

**Dependency categories (decide how to test a deepened module)**
1. In-process (pure/in-memory) → merge, test through new interface directly.
2. Local-substitutable (PGLite, in-memory FS) → stand-in runs in the suite; seam stays internal.
3. Remote but owned → **port** at the seam; HTTP/gRPC/queue adapter in prod, in-memory adapter in tests.
4. True external (Stripe, Twilio) → injected port, mock adapter in tests.
Replace, don't layer: once tests exist at the deep interface, delete old shallow-module unit tests.

**Hexagonal / Ports & Adapters** (when domain logic is tangled with I/O, or one use case has several entry points: HTTP/CLI/queue/cron)
- Dependencies point inward: adapters → application → domain; domain imports nothing external (no ORM/framework/SDK types).
- Use case = one input DTO → one output DTO; never reads `req`/`res`/queue metadata. Outbound ports model **capabilities**, not technologies (`PaymentGatewayPort`, `ClockPort`). Mapping lives in adapters. Errors translated across boundaries (infra → domain errors). Immutable transformations.
- Single explicit **composition root**; no hidden service locators or global singletons.
- Layout: `features/<x>/{domain, application/{ports/inbound,ports/outbound,use-cases}, adapters/{inbound,outbound}, composition}`. Go: small interfaces owned by the consumer, wired in `cmd/<app>/main.go`.
- Tests: pure domain tests (no mocks) · use-case tests with fake ports · shared port contract suites run against each adapter · inbound adapter mapping tests · adapter integration against real infra · E2E for critical journeys.
- Migration: strangler, one high-churn/low-blast-radius vertical slice at a time; characterization tests first; facade legacy behind ports; centralize wiring early; reversible toggle per slice. No big-bang rewrite.
- Anti-patterns: entities importing ORM models; use cases returning DB rows; adapters calling adapters; wiring scattered across files.

**Finding deepening opportunities** (improve-codebase-architecture flow)
1. Scope first (YAGNI): user's named area, else hot spots from `git log`.
2. Read `GLOSSARY.md` and `docs/adr/` in the area; don't re-litigate ADRs unless friction is real (flag "contradicts ADR-000N, worth reopening because…").
3. Explore for friction: bouncing between many small modules to understand one concept; shallow modules; pure functions extracted for testability while bugs live in the call sites; leaky coupling; untestable areas.
4. Present candidates (files, problem, solution, benefits in locality/leverage/test terms, before/after diagram, strength `Strong/Worth exploring/Speculative`, top pick). Don't propose interfaces until the user picks.
5. Grill the chosen one; **Design It Twice**: 3+ parallel sub-agents with radically different constraints (minimal 1–3 entry points; max flexibility; optimize common caller; ports & adapters). Compare on depth, locality, seam placement, then give an opinionated recommendation or hybrid.

**Domain language & decisions**
- `GLOSSARY.md` (or per-context glossaries under a `GLOSSARY-MAP.md`): challenge terms that conflict, sharpen fuzzy ones ("account" = Customer or User?), stress with edge-case scenarios, cross-check code vs stated behavior, update inline, no implementation detail in it. Create files lazily.
- **ADR only when all three hold**: hard to reverse, surprising without context, result of a real trade-off. Qualifies: architectural shape, inter-context integration, lock-in tech choices, ownership/scope boundaries, deliberate deviations, invisible constraints, non-obvious rejected alternatives.
- Format: `docs/adr/NNNN-slug.md`, sequential. Minimum is 1–3 sentences (context, decision, why). Add Status (`proposed|accepted|deprecated|superseded by ADR-NNNN`), Alternatives (pros/cons/why not), Consequences only when they add value. Never rewrite an accepted ADR; supersede it. Keep an index.

**Backend layering defaults** (Node/Express/Next, but generic): repository (data access behind an interface) → service (business logic) → handler/middleware (auth, logging, rate limit). Select only needed columns; batch to avoid N+1; transactions for multi-write invariants (DB function/RPC if the client lacks transactions); queue slow work instead of blocking the request (real queue, not an in-process array, in production).

Source detail: `mattpocock/engineering/codebase-design` (+DEEPENING, DESIGN-IT-TWICE), `mattpocock/engineering/improve-codebase-architecture`, `mattpocock/engineering/domain-modeling` (+ADR-FORMAT), `ecc/hexagonal-architecture`, `ecc/architecture-decision-records`, `ecc/backend-patterns`. Related: `mattpocock/in-progress/setup-ts-deep-modules` (dependency-cruiser enforced module boundaries), `ecc/module-governance`, `ecc/context-and-decisions`, `addyosmani/documentation-and-adrs`.

---

## 3. Error Handling & Resilience

- **Fail fast and loud** at the boundary where the error occurs. **Never swallow**: every catch handles, re-throws, or logs (with context).
- **Typed errors**: base `AppError {code, statusCode, details}` with subclasses (NotFound 404, Validation 422, Unauthorized 401, Forbidden 403, RateLimit 429 + retryAfter). TS: `Object.setPrototypeOf(this, new.target.prototype)` for `instanceof`. Python: exception hierarchy + framework handlers. Go: sentinel errors + `fmt.Errorf("...: %w", err)`, `errors.Is` at the handler; never lose the original.
- **Result type** (`{ok:true,value}|{ok:false,error}`) for expected, common failures (parsing, external calls).
- **One central API error handler**: AppError → its code/status; schema error → 422 with field details; unknown → log full context server-side, return generic `INTERNAL_ERROR`.
- **User messages ≠ developer messages**: map codes to friendly text; no stack traces, SQL, file paths in user-visible output. Errors are part of the API contract: document every code a client can get.
- **Retries**: exponential backoff **with jitter**, capped delay, bounded attempts, only for retriable errors (network/5xx/429), never 4xx. Pair retries of mutations with idempotency keys (section 1). Circuit-break flaky dependencies; set timeouts on every outbound call.
- **No fire-and-forget async** without a failure path. React: `ErrorBoundary` around render trees, with a recovery action.
- Fail closed (OWASP A10:2025 Mishandling of Exceptional Conditions).

Source detail: `ecc/error-handling`, `ecc/backend-patterns`, `addyosmani/security-and-hardening` (A10). Debugging live failures → `debugging.md`.

---

## 4. Security & Hardening

**Threat model first (5 minutes, before controls)**
1. Map trust boundaries: requests, forms, uploads, webhooks, third-party APIs, queues, **LLM output**, and "internal-looking" values written by processes you don't control (another process's argv/env, filenames on shared volumes, paths in job payloads). Trust follows who *wrote* a value, not which channel delivered it.
2. Name assets: credentials, PII, payment data, admin actions, money movement.
3. STRIDE per boundary: Spoofing (authn, signatures) · Tampering (integrity, parameterized queries, HTTPS) · Repudiation (audit log) · Info disclosure (encryption, field allowlists, generic errors) · DoS (rate limits, size caps, timeouts) · Elevation (authz, least privilege).
4. Abuse cases next to use cases; the first test is the misuse. Can't name the boundaries → not ready to secure it (A06 Insecure Design).

**Always**: validate external input at the boundary (schema, allowlist) · parameterize every query (SQL/NoSQL/shell) · framework auto-escaping for output · HTTPS everywhere · hash passwords (argon2/scrypt/bcrypt ≥12) · security headers · session cookies `HttpOnly; Secure; SameSite` · native dependency audit against the committed lockfile before every release.
**Ask a human first**: new/changed auth flows · new categories of sensitive data · new external integrations · CORS changes · upload handlers · rate-limit changes · granting elevated roles.
**Never**: commit secrets · log passwords/tokens/full card numbers · trust client-side validation · disable security headers · `eval`/`innerHTML` with user data · auth tokens in `localStorage` · stack traces/internals to users.

**Controls**
- **AuthZ on every request**, not just authN: the user must own or be permitted on *this* resource (IDOR, A01). Admin endpoints verify role. API keys least-scoped. JWTs: verify signature, expiry, issuer. Next.js Server Actions are public endpoints: authenticate AND authorize inside each. Supabase/Postgres: enable RLS on every table (`USING ((SELECT auth.uid()) = user_id)`).
- **Sessions/auth**: secret from env/secret manager, fail startup if missing; bounded `maxAge`; reset tokens ≤1h, single-use; login rate limit ≤10 per 15 min; optional lockout with notification; MFA for sensitive ops.
- **Cookies & CSRF** (stronger wins): `HttpOnly; Secure`; `SameSite=Lax` minimum, `Strict` where flows allow; `SameSite=None` only for intentional cross-site use **with** CSRF tokens or Fetch-Metadata (`Sec-Fetch-Site`) checks. CSRF tokens/double-submit on state-changing requests for cookie-authenticated apps.
- **Headers**: `Content-Security-Policy: default-src 'self'; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'` (tighten, never loosen; no `'unsafe-eval'` ever, no `'unsafe-inline'` unless nonce/hash + `'strict-dynamic'`; treat any exception as dated debt) · `Strict-Transport-Security: max-age=31536000` (`includeSubDomains` only after every subdomain serves HTTPS; `preload` a separate explicit decision) · `X-Content-Type-Options: nosniff` · `X-Frame-Options: DENY` · `X-XSS-Protection: 0` · `Referrer-Policy: strict-origin-when-cross-origin` · `Permissions-Policy: camera=(), microphone=(), geolocation=()`. Remove `X-Powered-By`; no production source maps.
- **CORS**: explicit origin allowlist from config; never `*` with credentials; never reflect arbitrary `Origin`.
- **XSS**: auto-escaping; if raw HTML is unavoidable, allowlist sanitizer (DOMPurify with explicit tags/attrs).
- **Responses**: strip `passwordHash`, reset tokens etc. via an allowlisted public projection; generic error bodies, details only in server logs.
- **Uploads**: allowlist MIME + extension, cap size, verify magic bytes when it matters, store outside webroot.
- **SSRF** (webhooks, import-from-URL, image proxies, link previews): allowlist scheme+host; resolve **all** DNS records, reject any non-unicast (loopback, `169.254.169.254`, private, unique-local, v4+v6); `redirect: 'error'`; close the DNS-rebinding gap by pinning the validated IP (keep Host/SNI) or using a filtering transport; re-check on retries.
- **Open redirects**: validate redirect targets against an allowlist.
- **Destructive ops on derived paths** (delete/move/overwrite): resolve symlinks, then require (a) under an allowlisted root, (b) at least one level below it, (c) ownership evidence read before the op (from authenticated state; an in-tree marker is self-attestation unless integrity-protected). On refusal log and stop; never fall back to a broader path. On shared volumes operate by descriptor/no-follow to avoid check/use races.
- **Rate limiting**: general API + strict auth/expensive endpoints, keyed by IP and user; **shared store** (Redis/gateway/platform limiter) once >1 instance or serverless; in-memory limiters are `max × instances` or never fire.
- **Secrets**: from env injected by a secret manager in production (rotation + access audit); `.env.example` committed with placeholders; `.env*`, `*.pem`, `*.key` gitignored; pre-commit check `git diff --cached -i -G'password|secret|api_key|token' --name-only` (prints file names only). **A secret that reached a remote is compromised: rotate first, then purge history.** Keep secrets out of argv, logs, traces, exceptions, model context.
- **Supply chain**: find the installation boundary (workspace root owning the lockfile); corroborate `packageManager`, lockfile, CI; stop on competing lockfiles; pin the manager. Frozen installs in CI (`npm ci`, `pnpm install --frozen-lockfile`, `yarn install --immutable`). Block dependency lifecycle scripts before first execution; approve minimally via the manager's native policy, commit it. Triage critical/high by **reachability** (runtime/build/test/deploy) and fix availability; never auto-apply `audit fix --force`; document deferrals with reason + review date. Audits miss new malicious/typosquatted packages: review ownership, maintenance, release age, provenance, transitive graph; verify registry signatures. SRI (`integrity` + `crossorigin`) on third-party CDN scripts. Don't serve lockfiles/`.npmrc`/`.git` publicly.
- **Privacy**: classify fields as added (non-personal / PII / sensitive: health, finance, location, biometrics, gov IDs, minors); collect only against a stated purpose; retention TTL and a working deletion path (incl. backups, caches, indexes, analytics); export/correct/delete rights; consent + DPA before sharing PII with analytics/ad/LLM vendors; region as config. Healthcare → `ecc/hipaa-compliance`, `ecc/healthcare-phi-compliance`.
- **AI/LLM features** (OWASP LLM Top 10 2025): model output is untrusted (LLM05): never into eval/SQL/shell/innerHTML/paths; parse → schema-validate → allowlisted action → encode. Prompt injection assumed (LLM01): the system prompt is not a security boundary; enforce permissions in code. Keep secrets, other tenants' data, full system prompt out of context (LLM02/07). Scope tools, validate every tool argument, confirm destructive actions (LLM06). Cap tokens, rate, recursion (LLM10). Partition RAG per tenant, validate docs before indexing (LLM08). Vet models/datasets/plugins (LLM03/04). Ground claims, human in loop (LLM09).
- **Agent runtimes** (tool gateways, memory, autonomous workers): map every `source → parser → validator → side effect` with its authorizing identity, size bounds, audit evidence, recovery path. Validate at the action boundary even if upstream validated. Allowlist identifiers (e.g. agent IDs `^[A-Za-z0-9_][A-Za-z0-9_-]*$`, ≤64), pass as argv after `--`, never via shell. Reject empty/whitespace env values. Workspace path containment: reject absolute/`..`/Windows-reserved names/trailing dot-space/`:`; resolve then component-aware containment; exclusive create; `0600` files/`0700` dirs; private runtime dir; cleanup in `finally`. Bound tool output bytes, strip control chars, explicit truncation marker, typed failure (never silent empty success). Irreversible actions require operation+resource authorization plus confirmation or scoped pre-approval; fail closed. Redact **before** values reach logs/traces; prove with a sentinel-secret capture test. Default external integrations read-only.
- **Cloud/infra**: least-privilege IAM (no `s3:*` on `*`), no root usage, MFA on privileged accounts, roles/OIDC not long-lived keys (CI uses OIDC, `permissions: contents: read`); DBs never public, SSH/RDP via VPN/bastion; flow logs; WAF + bot/DDoS protection; encrypted at rest/in transit; automated backups with PITR, `deletion_protection`, quarterly restore tests, RPO/RTO defined; security events logged with ≥90-day retention, tamper-resistant; branch protection, required review, secret + dependency + image scanning in CI.
- **Containers**: pinned tags/digests (never `:latest`), non-root user, `read_only`, `no-new-privileges`, `cap_drop: ALL`, no secrets in layers, `.dockerignore` excludes `.env`/`.git`.
- **Web3**: verify wallet signatures, validate recipient/amount/balance, no blind signing → see catalog (Web3).

**Perimeter audit (live domain, passive only)**: probe `/.git/HEAD` & `/.git/config` directly (a 403 on `/.git/` is not enough), `/docker-compose.yml`, dotenv paths, lockfiles, `/.npmrc` — report status + boolean signature only, never echo contents. CORS reflection of `Origin: https://evil-probe.invalid` + credentials = HIGH lead. Cache poisoning via `X-Forwarded-Host` only after proving cache-key isolation with random cache-busters (or on staging). HTTP→HTTPS 301/308; CSP/HSTS as above; cookies flags; random 404 route leaks no stack traces; `/.well-known/security.txt` (RFC 9116, unexpired); AI crawler rules in `robots.txt`/`llms.txt`, verify bots by FCrDNS/published ranges, never User-Agent. Perimeter checks cannot verify A01/A05/A06/A07/A09 internals: say so. Never destructive payloads or brute force.

**OWASP Top 10:2025 quick map** (cite with year): A01 Broken Access Control (incl. SSRF) · A02 Security Misconfiguration · A03 Software Supply Chain Failures · A04 Cryptographic Failures · A05 Injection · A06 Insecure Design · A07 Authentication Failures · A08 Software/Data Integrity Failures · A09 Security Logging & Alerting Failures · A10 Mishandling of Exceptional Conditions.

**Pre-ship security checklist**
- [ ] Threat model done; abuse-case tests exist (401 unauthenticated, 403 wrong role/owner, 4xx bad input, 429 over limit)
- [ ] No secrets in code or history; secrets via manager/env; `.gitignore` covers env/key files
- [ ] All input schema-validated (allowlists, lengths, ranges, formats); queries parameterized; output encoded
- [ ] AuthN + authZ (ownership/role) on every protected endpoint/action; RLS where applicable
- [ ] Cookies HttpOnly/Secure/SameSite; CSRF defense; CORS allowlist
- [ ] Security headers verified on real responses (proxies/CDNs strip them)
- [ ] Generic error bodies; no sensitive data in logs
- [ ] Rate limiting on auth/expensive endpoints, shared store
- [ ] SSRF allowlist; open-redirect check; upload restrictions; destructive-path containment
- [ ] Dependency audit clean of reachable critical/high; frozen installs; scripts gated
- [ ] LLM output validated/encoded; tool permissions scoped (if AI features)
- [ ] PII classified, minimized, retention + deletion/export working end-to-end
- [ ] Claude Code config audited (`.claude/`, hooks, MCP, agents) → `ecc/security-scan`, `ecc/mcp-dependency-review`

Rationalizations to reject: "internal tool", "add security later", "nobody would try", "framework handles it", "just a prototype", "just LLM text", "audit passed so deps are safe", "collect now, might need later", "handle deletions manually".

Source detail: `addyosmani/security-and-hardening` (+references/hardening-patterns.md, references/shared/security-checklist.md), `ecc/security-review` (+cloud-infrastructure-security.md), `ecc/web-perimeter-owasp-2025-audit`, `ecc/agent-security-hardening`, `ecc/security-scan`, `ecc/docker-patterns`. Hunting exploitable bugs in a repo → `ecc/security-bounty-hunter`; whole-repo quality/security audit → `ponytail/ponytail-audit` (see `review-quality.md`).

---

## 5. Performance

**Rule: measure before optimizing.** No evidence of a problem → don't optimize. Fix obvious anti-patterns (N+1, unbounded queries, missing image dimensions) as you write; defer micro-optimizations.

**Workflow: MEASURE → IDENTIFY → FIX (one thing) → VERIFY (keep/revert) → GUARD**
1. **Measure** with both synthetic (Lighthouse, DevTools Performance, CI) and field/RUM (`web-vitals`, CrUX, APM). Backend: APM, query logs with timing, `EXPLAIN ANALYZE`, p50/p95/p99 not averages. Profile on representative hardware (mid-range Android / 4–6× CPU throttle).
2. **Identify** by symptom:
   - First load: big bundle → splitting; slow TTFB (>800ms) → DNS (preconnect/dns-prefetch) / TCP-TLS (HTTP/2-3, edge, keep-alive) / server (profile, queries, cache); render-blocking CSS/JS.
   - Sluggish interaction: long tasks >50ms on main thread; re-renders; layout thrashing.
   - After navigation: API waterfalls, client N+1 fetches.
   - Backend: one endpoint slow → queries/indexes; all slow → pool, memory, CPU; intermittent → locks, GC, external deps.
   - Slow LCP → images/render-blocking/server; high CLS → missing dimensions, late content, font swap; poor INP → main-thread JS, big DOM updates; memory growth → leaks/unbounded caches; CPU spikes → sync heavy work, regex backtracking.
3. **Fix the identified bottleneck only.**
4. **Verify**: same command, same conditions, same budget (no cold-vs-warm cache); one change at a time; repeat runs, beat run-to-run variance. Keep only if past threshold with tests green. **Neutral = revert. Worse = revert. Improved but a test broke = revert.** Correctness gates the metric (dropping validation or caching what must be fresh is a regression). Commit with before/after numbers.
5. **Log every attempt** (kept and reverted) in the PR or `PERF.md`: idea · baseline→result · verdict · why. Read it before proposing experiments.
6. **Guard** the user-felt metric: synthetic CI budget (median/trend, not one noisy run) + field p75 alert using attributed web-vitals. Guard fires → new baseline first.

**Targets / budgets**: LCP ≤2.5s · INP ≤200ms · CLS ≤0.1 (needs-improvement ≤4.0s/≤500ms/≤0.25). Initial JS <200KB gz · CSS <50KB gz · above-fold image <200KB · fonts <100KB · API p95 <200ms · TTI <3.5s on 4G · Lighthouse ≥90. Enforce: `npx bundlesize`, `npx --package=@lhci/cli lhci autorun`.

**Backend fixes**
- **N+1**: join/include or batch fetch + map. **Unbounded fetch**: always `LIMIT` + stable order; select only needed columns; bulk ops not loops.
- **Indexes**: read the plan before and after. Seq Scan where index expected = missing/unusable; estimate off by 10× = stale stats → `ANALYZE` not a new index; `Sort` above scan = index doesn't cover ORDER BY. Composite = equality columns first, then range/sort; covering (`INCLUDE`) for hot reads; partial index for rare values; expression index for `lower(email)`; trigram/full-text for leading wildcards; GIN for jsonb/tsvector, BRIN for time-series. Every index taxes writes; drop unused/duplicate; an index that didn't change the plan is reverted.
- **Connection pools**: symptom = everything slows at once, time spent waiting for a connection, DB shows idle sessions. One pool per process; `instances × max < max_connections`; `connectionTimeoutMillis` to fail fast; find what holds connections (long transactions, missing `await`, leaked clients) before resizing; serverless/autoscale → pgbouncer/RDS Proxy, not bigger pools.
- **Caching**: only what's measured expensive and read ≫ written. Pick layer: in-process (per-instance drift) / shared Redis (hop + ops) / CDN (hard to recall). **Key includes every response input** (tenant, viewer, locale, permissions, flags) or you leak data across users. One invalidation strategy (TTL with stated staleness window / event-tag / versioned keys). Stampede protection (coalesce in-flight misses, distributed lock, or stale-while-revalidate). Negative-cache "not found" with a shorter TTL; never cache origin errors. Eviction + memory ceiling; monitor hit rate. Never cache balances, permissions, checkout inventory. Patterns: cache-aside (default), read-through, write-through (fresh reads), write-behind (loss window).
- Compression (gzip/brotli), CDN for static assets with `max-age=1y, immutable` + content hashing, no heavy sync work in handlers, health endpoint for LB.
- **Latency-critical paths** (realtime dashboards, market data, streaming agents, queues): track p50/p95/p99, throughput, freshness age, queue depth, hit rate, provider time, render time, correctness under load. Map the hot path segment by segment (`source → provider → ingest → queue → cache → edge → client stream → render`). Order: remove round trips → cache stable reads with freshness metadata → batch → move compute closer → split hot/cold → backpressure → stream only when it helps → canaries for stale data. Never hide stale data behind fast hits; never claim ms numbers without measurement. → `ecc/latency-critical-systems`. Bulk data movement/ETL → `ecc/data-throughput-accelerator`.

**Frontend fixes**
- Images: explicit `width`/`height` on `<img>` and `<source>`; LCP image `fetchpriority="high"`, never lazy; AVIF/WebP via `<picture>`, `srcset`/`sizes`; below-fold `loading="lazy" decoding="async"`.
- JS: route-level splitting + `lazy()`/`next/dynamic` for heavy rare features; statically analyzable `import()` paths; conditional imports (admin-only); preload on hover/focus; third-party scripts `async`/`defer`/after hydration with facades for heavy widgets. Barrels: tree-shaking removes unused code but barrels still cost module-graph work; prefer direct imports or Next `optimizePackageImports`, measure.
- INP: break long tasks (`scheduler.yield()`, `yieldToMain`, `postTask`, `isInputPending`), Web Workers for heavy compute, defer analytics/logging out of handlers, `requestIdleCallback` for deferrable work, `startTransition`/`useDeferredValue` for non-urgent updates.
- Rendering: animate only `transform`/`opacity` (animate the wrapper, not the SVG); batch DOM reads then writes; virtualize long lists (`@tanstack/react-virtual`); `content-visibility: auto` + `contain-intrinsic-size`; preserve bfcache (no `unload`, no `no-store` on HTML); critical CSS inline, no runtime CSS-in-JS cost.
- Fonts: ≤2–3 families × 2–3 weights; WOFF2 only; self-host; preload LCP fonts (`crossorigin`); `font-display: swap|optional`; `unicode-range` subsets; variable fonts; fallback metric overrides (`size-adjust`, `ascent-override`) to cut CLS; consider system stack.
- **React/Next priority order** (`ecc/react-performance`): (1) **waterfalls**: cheap sync checks before `await`, defer awaits into the branch that needs them, `Promise.all` independent work, start early/await late, Suspense close to data with reserved space, split RSC siblings into child components to parallelize; (2) **bundle**; (3) **server**: authorize every Server Action, `React.cache()` per-request dedupe, LRU/`unstable_cache` cross-request, no mutable module-level state on the server (cross-user leak), pass minimal props to Client Components, `after()` for post-response work; (4) **client fetching**: SWR/TanStack Query for shared data (never ad-hoc `useEffect` fetch), one shared global listener, passive scroll listeners, versioned small `localStorage`; (5) **re-renders**: don't subscribe to state used only in callbacks, select derived booleans, hoist default non-primitive props (`EMPTY`), primitive effect deps, derive during render not in `useEffect`, functional `setState`, lazy `useState` init, never define components inside components, `useRef` for transient values; memo only for proven-expensive work or identity (React Compiler makes manual memo review-only); (6) rendering: ternary not `&&` with numbers, `<Activity>` for hide/show, narrow `suppressHydrationWarning`, inline pre-hydration script for theme; (7) JS micro: `Map`/`Set` lookups, hoist RegExp, single-pass `flatMap`, loop for min/max.

**Perf checklist**
- [ ] Before/after numbers from identical measurement; delta beats variance
- [ ] Specific bottleneck identified; one change per measurement
- [ ] Neutral/worse/test-breaking changes reverted; attempts logged
- [ ] CWV in "Good"; bundle didn't grow unreviewed
- [ ] No N+1; lists paginated; new index justified by plan before/after
- [ ] New cache states its key inputs, staleness window, invalidation, stampede guard
- [ ] Synthetic budget and/or field monitor guards the metric
- [ ] Tests still pass

Source detail: `addyosmani/performance-optimization` (+references/optimization-patterns.md, references/shared/performance-checklist.md), `ecc/react-performance`, `ecc/latency-critical-systems`, `ecc/postgres-patterns`, `ecc/frontend-patterns`, `ecc/backend-patterns`. Benchmark tooling → `ecc/benchmark`, `ecc/benchmark-optimization-loop`. Perf regressions as bugs → `debugging.md`.

---

## 6. Frontend / UI Engineering & Design Quality

**Verify with what the project has**: run its own lint/type/test; don't install toolchains just to check; say what you couldn't run.

**Components**
- Colocate per component: `X.tsx`, `X.test.tsx`, `X.stories.tsx`, `use-x.ts`, `types.ts`. Components >200 lines → split.
- Composition over configuration (`<Card><CardHeader/>…`), compound components with context that throws outside its provider, focused single-purpose components.
- Separate data containers from presentational components. Every data view handles **loading (skeleton, not spinner, for content), empty (explain + next action), error (specific + retry), partial, success, permission** states; record why a state doesn't apply.
- Custom hooks for reusable state (`useToggle`, `useDebounce`); keep callbacks/fetchers in refs when callers pass inline functions to avoid fetch loops.
- Forms: schema validation, labels, field-linked errors (see 7); optimistic updates with rollback on error (TanStack `onMutate`/`onError`).
- Error boundaries around route/feature trees.

**State: pick the simplest that works**: local `useState` → lifted (2–3 siblings) → Context (theme/auth/locale; read-heavy) → URL params (filters, pagination, shareable) → server-state cache (TanStack Query/SWR) → global store (Zustand/Redux) for complex shared client state. Prop drilling >3 levels → context or restructure.

**Design system adherence**
- Semantic tokens (`text-primary`, `bg-surface`, `border-default`), never raw hex; spacing from the scale (no `13px`, `2.3rem`); radius/shadow/typography from the system. One `h1`, no skipped heading levels, headings only for headings.
- Contrast 4.5:1 text, 3:1 large text and UI; never color alone for meaning.
- Mobile-first responsive; test 320 / 768 / 1024 / 1440 px; stable dimensions for grids, toolbars, counters; long labels wrap cleanly.
- Generating/auditing a system: extract tokens (color, type, spacing, radius, shadow, breakpoints) → `design-tokens.json` + CSS custom properties + `DESIGN.md` rationale + preview; audit 10 dimensions (color consistency, type hierarchy, spacing rhythm, component consistency, responsive, dark mode completeness, purposeful animation, a11y, density, polish) with file:line fixes → `ecc/design-system`.

**Design direction (before coding)**: state purpose, audience (what they scan first), tone (utilitarian/editorial/technical/playful…), one memorable detail, constraints. Tools for daily use are dense, quiet, scannable; don't force landing-page composition onto them. First viewport shows the actual product/workflow. Use existing components/tokens/icons first. Real assets over filler. Optional reference-led flow: study 2–3 relevant screens → short design contract (job, primary action, states, responsive rules, patterns to reject) → rebuild in your own system; never copy branding/text/layout.

**Avoid the AI aesthetic**: purple/indigo/blue gradients everywhere, decorative blobs, glassmorphism without purpose, `rounded-2xl` on everything, generic centered hero, lorem ipsum, uniform oversized padding, stock card grids, cards inside cards, heavy layered shadows, scroll animations everywhere, one-hue palettes, UI text describing features the controls already show, new dependencies for flourishes.

**Polish details** (make interfaces feel better)
- Concentric radius: outer = inner + padding (or treat as separate surfaces). Optical alignment for icons/play/arrows.
- Borders for separation and focus; subtle layered transparent shadows for depth.
- `text-wrap: balance` on headings, `pretty` on short body; `tabular-nums` for counters, prices, timers, tables. Root `-webkit-font-smoothing: antialiased`.
- Images: neutral 1px inset outline (`rgba(0,0,0,.1)`, white alpha in dark mode), never brand-tinted.
- Motion: CSS transitions for interactive state (retargetable), keyframes for one-shot entrances; enter = opacity + small translateY (+blur), exit shorter (~150ms); press `scale(0.96)`; icon swaps cross-fade. **Never `transition: all` or `will-change: all`**; list properties. Motion clarifies state, never masks slowness; respect `prefers-reduced-motion`.
- Hit areas ≥40×40, ideally 44×44 (pseudo-element expansion, no overlap).
- Report polish reviews as Principle | Before | After rows with file paths.

**Rendered finish gate** (source inspection alone cannot pass): inspect the rendered UI at each target viewport; keyboard nav, visible focus, labels, contrast, reduced motion, touch targets; narrow/wide with long content; exercise every content state incl. partial data; keep screenshots/browser artifacts; fix and re-check. Report untested states honestly. Browser tooling → `addyosmani/browser-testing-with-devtools`, `ecc/browser-qa`, `ecc/click-path-audit`.

**UI checklist**
- [ ] No console errors; renders at 320/768/1024/1440
- [ ] Loading/empty/error/partial/success/permission states handled
- [ ] Tokens/spacing/type from the design system; no arbitrary values or inline styles
- [ ] Keyboard-complete; a11y checks pass (section 7)
- [ ] No AI-slop patterns; first viewport shows the real product
- [ ] Rendered finish gate done with artifacts

Source detail: `addyosmani/frontend-ui-engineering`, `ecc/frontend-patterns`, `ecc/frontend-design-direction`, `ecc/design-system`, `ecc/make-interfaces-feel-better`, `ecc/motion-foundations`. Framework specifics → catalog (Web frameworks, Frontend & design).

---

## 7. Accessibility (WCAG 2.2 AA)

Target **WCAG 2.2 AA** (supersedes any 2.1 references). POUR: Perceivable, Operable, Understandable, Robust. Accessibility is a legal and quality requirement, internal tools included.

**Build rules**
- Semantic HTML first; ARIA only as a bridge (wrong ARIA is worse than none). `<button>` for actions, `<a href>` for navigation; never clickable `div`/`span`. If unavoidable: `role="button"`, `tabIndex={0}`, Enter on keydown and Space on keyup (preventDefault on Space keydown).
- Menus, dialogs, tabs, listboxes, comboboxes: follow WAI-ARIA APG patterns exactly (`aria-expanded`, `aria-controls`, `aria-haspopup`, `role="option"` + `aria-selected`, arrow keys, Escape).
- Names: visible `<label htmlFor>` for every input (placeholder is not a label); `aria-label` for icon-only buttons (icon `aria-hidden`); `aria-labelledby` when visible text exists; `aria-describedby` for hints/errors. No `aria-label` on role-less divs; never `aria-hidden` on focusable elements.
- Forms: required via `required` + `aria-required` and not by color/asterisk alone (`<span aria-hidden>*</span>`); errors specific, linked via `aria-describedby`, `aria-invalid`, `role="alert"`; submission error summary that receives focus; suggestions for correction (3.3.3); don't ask for the same data twice (3.3.7 Redundant Entry); `autocomplete` on known fields.
- Focus: visible indicator on all backgrounds (2.4.11), never removed without replacement; order matches visual order; no positive `tabIndex`; skip-to-content link; modals contain focus, close on Escape, restore focus to the trigger (use a focus-trap library for full Tab cycling); menus restore focus on close; route changes move focus sensibly; no keyboard traps (2.1.2).
- Dynamic content: `role="status"`/`aria-live="polite"` for status, `role="alert"`/assertive only for urgent errors; `aria-busy` on loading regions.
- Images: meaningful `alt` (no "image of"); decorative `alt=""` (+`aria-hidden`); complex charts get text summaries.
- Visual: contrast 4.5:1 text, 3:1 large text (≥24px, or ≥18.67px bold) and UI components; never round a failing ratio up; no color-only meaning (text/icon/pattern too); links distinguishable beyond color; text resizes to 200% and reflows at 400% without loss; nothing flashing >3/s; respect `prefers-reduced-motion`; works in forced-colors mode.
- Targets: ≥24×24 CSS px or the SC 2.5.8 spacing/exception (AA); 44×44 is the AAA target (2.5.5) and the native iOS/Android norm (44pt/48dp). Single-pointer alternative for drag (2.5.7).
- Page: `<html lang>`, descriptive `<title>`, one `h1`, sequential headings, landmarks (`nav` with `aria-label` when multiple), tables with `<th scope>`, `role="list"` where list semantics are stripped by CSS, no autoplaying media without controls.
- Native: iOS `.accessibilityLabel/Hint/AddTraits`, `AccessibilityNotification.Announcement` (iOS 17+); Android Compose `contentDescription`, `semantics { role, stateDescription, liveRegion }`.

**Audit workflow**
1. New UI construction → build rules above (frontend-ui-engineering); audit once it exists.
2. Automated smoke test: `npx --yes @axe-core/cli@4.13.0 <url> --exit` and `npx --yes pa11y@9.1.1 <url>`; Lighthouse a11y; triage Critical (blocks AT) → Serious → Moderate → Minor; confirm each in the browser (false positives exist).
3. Manual (mandatory; automated ≠ conformance): keyboard (Tab everything, Enter/Space, Escape closes, arrows in composites, no traps, visible focus); screen reader (VoiceOver/NVDA/Orca) by headings, landmarks, links, forms, dynamic updates; visual (contrast, 200% zoom, forced colors, reduced motion, focus visibility).
4. Fix root cause (native element, label, alt) → ARIA as bridge only → re-run automated + manual.
5. Report screen-reader results with the named browser+AT pair; untested = say "manual, untested", never "verified".

**A11y checklist**
- [ ] No Critical/Serious automated violations
- [ ] Keyboard: every interactive element reachable/operable, focus visible, order logical, no traps
- [ ] Labels on all inputs; errors linked and announced; icon buttons named
- [ ] Heading/landmark structure verified with a screen reader (named pair)
- [ ] Contrast 4.5/3/3; no color-only meaning
- [ ] Dynamic updates announced; modals trap + restore focus
- [ ] 200% zoom / reflow OK; reduced motion respected
- [ ] Targets meet 2.5.8 (24px) or exception; 44px where layout allows

Source detail: `addyosmani/accessibility-engineering` (+references/shared/accessibility-checklist.md), `addyosmani/frontend-ui-engineering`, `ecc/accessibility`, `ecc/frontend-a11y`. Localization a11y → `ecc/i18n-sync`, `ecc/yoruba-localization-testing`.

---

## 8. Observability & Instrumentation

Instrument as you build, like tests. Not for live debugging (→ `debugging.md`) or launch-day monitoring sequence (→ `git-shipping.md`).

1. **Define "working" first**: write 2–4 questions on-call will ask (e.g. first-attempt vs retry success rate; why permanent failures happen; is the provider slow). Every signal maps to a question.
2. **Pick the signal**: metrics say **that** something is wrong (aggregate, cheap), traces say **where** (per request, sampled), logs say **why** (per event).
3. **Structured logs**: JSON, stable event name + machine fields (`{event:'payment_failed', paymentId, provider, errorCode, attempt}`), never string interpolation. Levels: `error` invariant broken/someone may act · `warn` degraded but handled · `info` significant business event · `debug` off in prod. **Correlation ID** generated/accepted at the boundary (`x-request-id`), on every line, span, outbound call, and queue message. When several entry points (scheduler, replay endpoint, CLI) write one sink, stamp an `entryPoint` field where the run starts and propagate it like the correlation ID. **Never log secrets, tokens, passwords, full PII, whole bodies, or auth headers**; allowlist fields; external calls logged as endpoint/status/latency/attempt only. Use a real logger, not `console.log`.
4. **Metrics**: RED (Rate, Errors, Duration) per endpoint and per external dependency; USE (Utilization, Saturation, Errors) per resource (pools, queues, hosts); queue depth + processing time per worker. Latency as **histograms**, read p50/p95/p99, never averages. **Cardinality**: labels from small fixed sets (route template, `status_class="5xx"`, provider); never user/tenant IDs, emails, request IDs, raw URLs, error text. OpenTelemetry metrics API is the vendor-neutral path; Prometheus is one backend.
5. **Tracing**: OpenTelemetry initialized before other imports, auto-instrumentation for HTTP/gRPC/DB; W3C `traceparent` propagated across every HTTP call and queue message; manual spans only for meaningful units (`chargeProvider`) with filterable attributes; no secrets/PII as attributes; low-rate head sampling, keep 100% of errors via tail sampling when available.
6. **Alerting**: page on **symptoms** (error rate >1%/5min, p99 >2s, queue age >10min), dashboard the causes (CPU, disk, restarts). Every alert actionable (else delete), linked to a runbook, threshold/duration justified by SLO or history, two severities only (page / ticket), test-fired once. **Runbooks** in `docs/runbooks/<alert>.md`, minimum three lines: what it means, first check/query, escalation; update after every incident that used it.
7. **Dashboards**: service health (errors, p99, traffic, saturation), per-dependency panel, answers the on-call questions, sensible default range (1–6h). Grafana/SigNoz builders → `ecc/dashboard-builder`.
8. **Verify the telemetry**: force an error in staging and find it by request ID (structured, not `[object Object]`); test traffic yields expected series/labels; follow one request across services with no broken spans; fire each alert once; diagnose an induced failure from telemetry alone.

**Pre-launch gate**: logs flowing to the aggregator · RED dashboards for new endpoints/deps · ≥1 symptom alert with runbook, test-fired · cross-service trace works · on-call knows where runbooks live. Also security-event logging (failed auth, admin actions) with retention (A09). Post-deploy URL/SSE checks → `ecc/canary-watch`; production readiness audit → `ecc/production-audit`.

Red flags: feature with retries/queues/external calls and zero new telemetry; interpolated log strings; orphan lines with no request ID; user IDs as metric labels; averages only; daily-firing ignored alerts; cause-based pages while user error rate is unmonitored; secrets in logs.

Source detail: `addyosmani/observability-and-instrumentation` (+references/shared/observability-checklist.md), `ecc/backend-patterns` (logging), `ecc/security-review/cloud-infrastructure-security.md` (logging), `ecc/dashboard-builder`, `ecc/canary-watch`.

---

## 9. Data, Migrations & Deploy Safety (quick rules)

**Postgres**: `bigint` IDs, `text` not `varchar(255)`, `timestamptz`, `numeric` for money, `boolean` flags. UPSERT via `ON CONFLICT … DO UPDATE`. Cursor pagination `WHERE id > $last ORDER BY id LIMIT n`. Job queues with `FOR UPDATE SKIP LOCKED`. Index every FK (query to find unindexed FKs); `pg_stat_statements` for slow queries; watch dead tuples/bloat. Set `statement_timeout` and `idle_in_transaction_session_timeout`; `REVOKE ALL ON SCHEMA public FROM public`; RLS policies wrap `auth.uid()` in `(SELECT …)`.

**Migrations**: every change is a migration file (never manual prod SQL); forward-only in prod (rollback = new forward migration); immutable once deployed; schema (DDL) and data (DML/backfill) in separate migrations; test against production-sized data; UP+DOWN or explicitly irreversible; review lock modes, set `lock_timeout`, keep DDL transactions short.
- Add column: nullable or non-volatile default (still takes ACCESS EXCLUSIVE briefly); `NOT NULL` without default on a populated table fails → add nullable, backfill, then constrain.
- Index: `CREATE INDEX CONCURRENTLY` (not inside a transaction; ORMs need a hand-written migration).
- Rename/retype: **expand-contract**: add new → deploy dual-write (reads old) → drain old-only writers → backfill in committed PK-range batches copying current values in-SQL (`IS DISTINCT FROM`) → verify zero mismatches → read new, still dual-write through rollback window → move constraints/indexes → drain old readers → new-only → drop old in a later separate migration.
- Drop column: remove code references and deploy first; drop next release (Django `SeparateDatabaseAndState`).
- Large updates: batched, committed per batch, `SKIP LOCKED`, progress reporting.

**Deploy**: rolling (default; requires backward-compatible changes) · blue-green (instant switch-back, 2× infra) · canary (5% → 50% → 100% on metrics). Multi-stage Dockerfiles, pinned versions, non-root, `HEALTHCHECK`, deps copied first for layer cache, `.dockerignore`, resource limits; Compose for local dev only (not prod orchestration); bind internal ports to `127.0.0.1` or omit. Liveness/readiness/startup probes; `/health` cheap, `/health/detailed` checks deps and returns 503 when degraded. Twelve-factor config validated at startup with a schema (fail fast). Rollback: previous artifact tagged, migrations backward-compatible, feature flags, rollback rehearsed in staging. Pipeline: PR = lint → typecheck → unit → integration → preview; main = … → image → staging → smoke → prod. Full shipping/CI process → `git-shipping.md`.

Source detail: `ecc/postgres-patterns`, `ecc/database-migrations` (+examples/*.sql), `ecc/deployment-patterns`, `ecc/docker-patterns`, `addyosmani/deprecation-and-migration`, `addyosmani/ci-cd-and-automation`.

---

## 10. Domain Routing Catalog

Find the row whose keywords match the task, then Read `library/<path>/SKILL_SOURCE.md` (supporting `.md` files sit beside it). Every ECC skill is listed exactly once; non-ECC domain skills are included; remaining process skills are indexed at the end so nothing is unreachable. Path shorthand `ecc/x` = `library/ecc/x/SKILL_SOURCE.md`.

### 10.1 Languages

| Trigger keywords | Skill | Path |
|---|---|---|
| Python idioms, PEP 8, type hints, dataclasses | python-patterns | ecc/python-patterns |
| pytest, fixtures, mocking, parametrize, Python TDD | python-testing | ecc/python-testing |
| Windows Python installer, Nuitka, packaging exe | generating-python-installer | ecc/generating-python-installer |
| TypeScript strict types, generics, narrowing, tsconfig | typescript-patterns | ecc/typescript-patterns |
| Bun runtime/package manager/bundler/test, Bun vs Node | bun-runtime | ecc/bun-runtime |
| Vite config, plugins, HMR, env vars, proxy | vite-patterns | ecc/vite-patterns |
| `as` assertions in tests → shoehorn | migrate-to-shoehorn | mattpocock/misc/migrate-to-shoehorn |
| TS monorepo deep modules, dependency-cruiser boundaries | setup-ts-deep-modules | mattpocock/in-progress/setup-ts-deep-modules |
| Husky, lint-staged, Prettier pre-commit | setup-pre-commit | mattpocock/misc/setup-pre-commit |
| Go idioms, interfaces, goroutines, errors | golang-patterns | ecc/golang-patterns |
| Go table-driven tests, benchmarks, fuzzing | golang-testing | ecc/golang-testing |
| Rust ownership, traits, error handling, concurrency | rust-patterns | ecc/rust-patterns |
| Rust unit/integration/async/property tests | rust-testing | ecc/rust-testing |
| Java naming, immutability, Optional, streams (Spring/Quarkus) | java-coding-standards | ecc/java-coding-standards |
| JPA, Hibernate entities, relationships, N+1 | jpa-patterns | ecc/jpa-patterns |
| MyBatis mappers, XML SQL, result maps | mybatis-patterns | ecc/mybatis-patterns |
| tinystruct Java framework, dispatcher scripts | tinystruct-patterns | ecc/tinystruct-patterns |
| Kotlin idioms, null safety, sealed classes, DSLs | kotlin-patterns | ecc/kotlin-patterns |
| Kotest, MockK, coroutine tests | kotlin-testing | ecc/kotlin-testing |
| Kotlin coroutines, Flow, StateFlow, structured concurrency | kotlin-coroutines-flows | ecc/kotlin-coroutines-flows |
| JetBrains Exposed ORM, DSL/DAO, HikariCP | kotlin-exposed-patterns | ecc/kotlin-exposed-patterns |
| Ktor server, routing DSL, plugins, Koin | kotlin-ktor-patterns | ecc/kotlin-ktor-patterns |
| C++ Core Guidelines, RAII, modern C++ | cpp-coding-standards | ecc/cpp-coding-standards |
| GoogleTest, CTest, C++ test failures | cpp-testing | ecc/cpp-testing |
| C#/.NET idioms, DI, async/await | dotnet-patterns | ecc/dotnet-patterns |
| xUnit, FluentAssertions, .NET integration tests | csharp-testing | ecc/csharp-testing |
| F# tests, FsUnit, Unquote, FsCheck | fsharp-testing | ecc/fsharp-testing |
| Swift actors, thread-safe persistence | swift-actor-persistence | ecc/swift-actor-persistence |
| Swift 6.2 concurrency, @concurrent, MainActor | swift-concurrency-6-2 | ecc/swift-concurrency-6-2 |
| Swift protocol DI, Swift Testing mocks | swift-protocol-di-testing | ecc/swift-protocol-di-testing |
| Dart null safety, Flutter state, widgets | dart-flutter-patterns | ecc/dart-flutter-patterns |
| Flutter/Dart code review checklist | flutter-dart-code-review | ecc/flutter-dart-code-review |
| PHP Laravel architecture, Eloquent, queues | laravel-patterns | ecc/laravel-patterns |
| Laravel auth, policies, CSRF, mass assignment | laravel-security | ecc/laravel-security |
| PHPUnit, Pest, Laravel factories, HTTP tests | laravel-tdd | ecc/laravel-tdd |
| Laravel lint/static analysis/test verification loop | laravel-verification | ecc/laravel-verification |
| find/evaluate Laravel packages (LaraPlugins MCP) | laravel-plugin-discovery | ecc/laravel-plugin-discovery |
| Ruby on Rails 7.1/8 structure, ActiveRecord, Hotwire | rails-patterns | ecc/rails-patterns |
| Rails security, strong params, prod config | rails-security | ecc/rails-security |
| Modern Perl 5.36+ idioms | perl-patterns | ecc/perl-patterns |
| Perl taint mode, safe exec, input validation | perl-security | ecc/perl-security |
| Test2::V0, Test::More, prove | perl-testing | ecc/perl-testing |
| Godot 4 GDScript, scenes, signals | godot-patterns | ecc/godot-patterns |
| Godot headless tests, gdUnit4 | godot-testing | ecc/godot-testing |
| cross-language naming/readability/immutability baseline | coding-standards | ecc/coding-standards |
| typed errors, retries, circuit breakers (TS/Py/Go) | error-handling | ecc/error-handling |

### 10.2 Web frameworks & backend

| Trigger keywords | Skill | Path |
|---|---|---|
| React 18/19 hooks, server/client components | react-patterns | ecc/react-patterns |
| React Testing Library, Vitest/Jest, MSW | react-testing | ecc/react-testing |
| React/Next perf: waterfalls, bundle, re-renders | react-performance | ecc/react-performance |
| React/Next components, state, data fetching patterns | frontend-patterns | ecc/frontend-patterns |
| Next.js 16, Turbopack, caching, build | nextjs-turbopack | ecc/nextjs-turbopack |
| Vue 3 Composition API, reactivity, Pinia | vue-patterns | ecc/vue-patterns |
| Nuxt 4 hydration safety, route rules, lazy loading | nuxt4-patterns | ecc/nuxt4-patterns |
| screenshots/design exports → Vue components | ui-to-vue | ecc/ui-to-vue |
| Angular components, signals, architecture | angular-developer | ecc/angular-developer |
| Django architecture, DRF, ORM, caching | django-patterns | ecc/django-patterns |
| Django security, CSRF, auth, SQLi | django-security | ecc/django-security |
| pytest-django, factory_boy, Django TDD | django-tdd | ecc/django-tdd |
| Django verification loop (mypy/ruff/tests) | django-verification | ecc/django-verification |
| Celery tasks, beat scheduling, retries | django-celery | ecc/django-celery |
| FastAPI, Pydantic v2, dependency injection | fastapi-patterns | ecc/fastapi-patterns |
| Spring Boot layered services, REST, data | springboot-patterns | ecc/springboot-patterns |
| Spring Security authn/authz, headers | springboot-security | ecc/springboot-security |
| JUnit 5, MockMvc, Testcontainers | springboot-tdd | ecc/springboot-tdd |
| Spring Boot build + SpotBugs/PMD verification | springboot-verification | ecc/springboot-verification |
| NestJS modules, providers, guards, DTOs | nestjs-patterns | ecc/nestjs-patterns |
| Quarkus 3, Camel messaging, REST | quarkus-patterns | ecc/quarkus-patterns |
| Quarkus JWT/OIDC, @RolesAllowed | quarkus-security | ecc/quarkus-security |
| Quarkus TDD, REST Assured | quarkus-tdd | ecc/quarkus-tdd |
| Quarkus build/static-analysis verification | quarkus-verification | ecc/quarkus-verification |
| Node/Express/Next API routes, repo/service layers, caching | backend-patterns | ecc/backend-patterns |
| REST naming, status codes, pagination, versioning | api-design | ecc/api-design |
| one authoritative contract for FE/BE or services | contract-first | ecc/contract-first |
| new API connector/provider matching repo patterns | api-connector-builder | ecc/api-connector-builder |
| ports & adapters, domain boundaries | hexagonal-architecture | ecc/hexagonal-architecture |
| MCP server (Node/TS SDK), tools/resources, Zod | mcp-server-patterns | ecc/mcp-server-patterns |
| transactional email via Mailtrap | mailtrap-email-integration | ecc/mailtrap-email-integration |
| X/Twitter API posting, timelines, search | x-api | ecc/x-api |

### 10.3 Frontend, design, a11y, i18n

| Trigger keywords | Skill | Path |
|---|---|---|
| production UI, components, layouts (generic) | frontend-ui-engineering | addyosmani/frontend-ui-engineering |
| design direction, less generic, distinctive UI | frontend-design-direction | ecc/frontend-design-direction |
| design tokens, design system generate/audit, AI slop | design-system | ecc/design-system |
| UI polish: radius, shadows, motion, hit areas | make-interfaces-feel-better | ecc/make-interfaces-feel-better |
| motion tokens, springs, reduced motion | motion-foundations | ecc/motion-foundations |
| button/modal/toast/stagger animations (React) | motion-patterns | ecc/motion-patterns |
| drag & drop, gestures, text/scroll animation | motion-advanced | ecc/motion-advanced |
| WCAG 2.2 web/iOS/Android, cross-platform a11y | accessibility | ecc/accessibility |
| React/Next a11y: forms, ARIA, focus | frontend-a11y | ecc/frontend-a11y |
| a11y audit, axe-core, pa11y, remediation | accessibility-engineering | addyosmani/accessibility-engineering |
| iOS 26 Liquid Glass design | liquid-glass-design | ecc/liquid-glass-design |
| HTML animated slide decks, PPT → web | frontend-slides | ecc/frontend-slides |
| live-editable UI mockup canvas | ui-canvas | ecc/ui-canvas |
| record UI demo video with Playwright | ui-demo | ecc/ui-demo |
| SEO technical/on-page audit | seo | ecc/seo |
| locale JSON translation sync | i18n-sync | ecc/i18n-sync |
| Yoruba tone marks, bilingual UI tests | yoruba-localization-testing | ecc/yoruba-localization-testing |
| Bengali text, Unicode normalization | bengali-nlp | ecc/bengali-nlp |

### 10.4 Data & storage

| Trigger keywords | Skill | Path |
|---|---|---|
| PostgreSQL schema, indexes, RLS, tuning | postgres-patterns | ecc/postgres-patterns |
| MySQL/MariaDB schema, replication, pooling | mysql-patterns | ecc/mysql-patterns |
| Redis caching, locks, rate limiting, streams | redis-patterns | ecc/redis-patterns |
| ClickHouse analytics, query optimization | clickhouse-io | ecc/clickhouse-io |
| Prisma schema, queries, transactions | prisma-patterns | ecc/prisma-patterns |
| migrations, expand-contract, backfills (Prisma/Drizzle/Kysely/Django/golang-migrate) | database-migrations | ecc/database-migrations |
| ingestion/backfill/ETL throughput bottleneck | data-throughput-accelerator | ecc/data-throughput-accelerator |
| SHA-256 content-hash cache for file processing | content-hash-cache-pattern | ecc/content-hash-cache-pattern |
| parse structured text: regex vs LLM | regex-vs-llm-structured-text | ecc/regex-vs-llm-structured-text |
| scraping agent for public sources | data-scraper-agent | ecc/data-scraper-agent |
| knowledge base ingestion/sync/retrieval | knowledge-ops | ecc/knowledge-ops |

### 10.5 Infrastructure, DevOps, performance, observability, security

| Trigger keywords | Skill | Path |
|---|---|---|
| Dockerfile, Compose, container security | docker-patterns | ecc/docker-patterns |
| Kubernetes workloads, probes, RBAC, HPA | kubernetes-patterns | ecc/kubernetes-patterns |
| Terraform/OpenTofu layout, state, modules | terraform-patterns | ecc/terraform-patterns |
| CI/CD, blue-green/canary, health checks, rollback | deployment-patterns | ecc/deployment-patterns |
| CI pipelines, quality gates (generic) | ci-cd-and-automation | addyosmani/ci-cd-and-automation |
| OCI images, SBOM/provenance, microVM (pf CLI) | platform-factory | ecc/platform-factory |
| Uncloud cluster, `uc` CLI, Caddy ingress | uncloud | ecc/uncloud |
| Flox/Nix reproducible dev environments | flox-environments | ecc/flox-environments |
| Nasiko CLI install/status/uninstall | nasiko-control-plane | ecc/nasiko-control-plane |
| open CLI in a visible terminal window, shell-free | terminal-opener | ecc/terminal-opener |
| run repo commands with evidence | terminal-ops | ecc/terminal-ops |
| Grafana/SigNoz operator dashboards | dashboard-builder | ecc/dashboard-builder |
| post-release URL/SSE monitoring | canary-watch | ecc/canary-watch |
| production readiness audit (local evidence) | production-audit | ecc/production-audit |
| logging, metrics, tracing, alerts (generic) | observability-and-instrumentation | addyosmani/observability-and-instrumentation |
| perf (generic): measure-first, CWV, N+1, caching | performance-optimization | addyosmani/performance-optimization |
| Core Web Vitals/API baselines, regressions | benchmark | ecc/benchmark |
| bounded benchmark-guided improvement loop | benchmark-optimization-loop | ecc/benchmark-optimization-loop |
| p95/p99, freshness, realtime hot paths | latency-critical-systems | ecc/latency-critical-systems |
| security (generic): threat model, OWASP, supply chain | security-and-hardening | addyosmani/security-and-hardening |
| security checklist: auth, input, secrets, payments | security-review | ecc/security-review |
| scan `.claude/` config with AgentShield | security-scan | ecc/security-scan |
| live domain perimeter audit, OWASP 2025, headers | web-perimeter-owasp-2025-audit | ecc/web-perimeter-owasp-2025-audit |
| exploitable bounty-worthy bugs in a repo | security-bounty-hunter | ecc/security-bounty-hunter |
| agent runtime/tool gateway hardening | agent-security-hardening | ecc/agent-security-hardening |
| MCP config mutable package refs review | mcp-dependency-review | ecc/mcp-dependency-review |
| install external repo-scan skill (pinned) | repo-scan | ecc/repo-scan |
| block destructive commands (careful/freeze modes) | safety-guard | ecc/safety-guard |
| hooks blocking dangerous git commands | git-guardrails-claude-code | mattpocock/misc/git-guardrails-claude-code |
| reverse engineer binaries/Electron/SQLite/JS bundles | leanrea | ecc/leanrea |
| Windows desktop E2E (WPF/WinForms/Qt, pywinauto) | windows-desktop-e2e | ecc/windows-desktop-e2e |

### 10.6 Mobile

| Trigger keywords | Skill | Path |
|---|---|---|
| SwiftUI, @Observable, navigation | swiftui-patterns | ecc/swiftui-patterns |
| Apple FoundationModels on-device LLM | foundation-models-on-device | ecc/foundation-models-on-device |
| iOS app icons from SF Symbols | ios-icon-gen | ecc/ios-icon-gen |
| Android/KMP clean architecture, modules | android-clean-architecture | ecc/android-clean-architecture |
| Jetpack Compose / Compose Multiplatform | compose-multiplatform-patterns | ecc/compose-multiplatform-patterns |
| React Native, Expo Router | react-native-patterns | ecc/react-native-patterns |
(Also Swift, Kotlin, Flutter rows in 10.1.)

### 10.7 ML, AI & LLM apps

| Trigger keywords | Skill | Path |
|---|---|---|
| PyTorch models, training loops, GPU | pytorch-patterns | ecc/pytorch-patterns |
| production MLE: data contracts, reproducible training | mle-workflow | ecc/mle-workflow |
| adding ML to a product, methodology | ml-adoption-playbook | ecc/ml-adoption-playbook |
| recommendation/ranking/feed pipelines | recsys-pipeline-architect | ecc/recsys-pipeline-architect |
| LLM cost: model routing, budgets | cost-aware-llm-pipeline | ecc/cost-aware-llm-pipeline |
| prompt caching hit rate | prompt-caching-strategy | ecc/prompt-caching-strategy |
| improve a draft prompt, route to ECC skills | prompt-optimizer | ecc/prompt-optimizer |
| audit 12-layer agent/LLM app stack | agent-architecture-audit | ecc/agent-architecture-audit |
| agent tool definitions, action space design | agent-harness-construction | ecc/agent-harness-construction |
| eval-driven development, capability evals | eval-harness | ecc/eval-harness |
| regression tests for AI-assisted dev | ai-regression-testing | ecc/ai-regression-testing |
| GPU inventory/RFQ (Itô) | ito-compute | ecc/ito-compute |
| model serving on Itô booking | ito-inference | ecc/ito-inference |
| ML training on Itô booking | ito-training | ecc/ito-training |
| fal.ai image/video/audio generation | fal-ai-media | ecc/fal-ai-media |
| agent persona/SOUL.md (OpenClaw) | openclaw-persona-forge | ecc/openclaw-persona-forge |
| shared-channel agent comms policy | counterparty-channel-discipline | ecc/counterparty-channel-discipline |
| approval loop for agent-drafted outbound messages | operator-approval-loop | ecc/operator-approval-loop |
| up-to-date library docs via Context7 | documentation-lookup | ecc/documentation-lookup |
(Agent harness/orchestration skills: 10.14.)

### 10.8 Media, video & creative

| Trigger keywords | Skill | Path |
|---|---|---|
| Manim explainer animations | manim-video | ecc/manim-video |
| Remotion React video | remotion-video-creation | ecc/remotion-video-creation |
| AI-assisted footage editing | video-editing | ecc/video-editing |
| VideoDB ingest/search/edit video & audio | videodb | ecc/videodb |
| ship vertical video to TikTok/Shorts/Reels | short-video-distribution | ecc/short-video-distribution |
| music-video aesthetic direction (hyperpop etc.) | taste | ecc/taste |
| generate/cut video from a style pack | taste-application | ecc/taste-application |
| distill reference videos into a style pack | taste-distillation | ecc/taste-distillation |
| multimodal asset discovery, EDL/FCPXML, provenance | tasteforge-video | ecc/tasteforge-video |
| Blender rigs, poses, retargeting inspection | blender-motion-state-inspection | ecc/blender-motion-state-inspection |
| course exercise directory scaffolding | scaffold-exercises | mattpocock/misc/scaffold-exercises |

### 10.9 Content, marketing, sales & comms

| Trigger keywords | Skill | Path |
|---|---|---|
| articles, blog posts, tutorials, newsletters | article-writing | ecc/article-writing |
| brand identity interview | brand-discovery | ecc/brand-discovery |
| writing style profile from real posts | brand-voice | ecc/brand-voice |
| platform-native content systems | content-engine | ecc/content-engine |
| crosspost X/LinkedIn/Threads/Bluesky | crosspost | ecc/crosspost |
| schedule posts across 13 platforms | social-publisher | ecc/social-publisher |
| prune/grow X & LinkedIn network | connections-optimizer | ecc/connections-optimizer |
| warm-intro social graph ranking | social-graph-ranker | ecc/social-graph-ranker |
| lead intelligence & outreach pipeline | lead-intelligence | ecc/lead-intelligence |
| marketing campaign plan & execution | marketing-campaign | ecc/marketing-campaign |
| market research, due diligence | market-research | ecc/market-research |
| competitive landscape scoping | competitive-platform-analysis | ecc/competitive-platform-analysis |
| competitor profile scoring (9 dimensions) | benchmark-methodology | ecc/benchmark-methodology |
| competitive report assembly | competitive-report-structure | ecc/competitive-report-structure |
| pitch decks, investor memos | investor-materials | ecc/investor-materials |
| investor cold emails, updates | investor-outreach | ecc/investor-outreach |
| mailbox triage, drafting, follow-ups | email-ops | ecc/email-ops |
| read/reply texts & messages | messages-ops | ecc/messages-ops |
| GitHub/Linear/desktop notifications | unified-notifications-ops | ecc/unified-notifications-ops |
| Google Drive/Docs/Sheets/Slides workflows | google-workspace-ops | ecc/google-workspace-ops |
| article writing: mine fragments / beats / shape | writing-fragments, writing-beats, writing-shape | mattpocock/in-progress/writing-fragments · writing-beats · writing-shape |

### 10.10 Business ops, finance, health, legal, logistics, manufacturing

| Trigger keywords | Skill | Path |
|---|---|---|
| subscriptions, refunds, churn, billing support | customer-billing-ops | ecc/customer-billing-ops |
| revenue, pricing, billing-model truth | finance-billing-ops | ecc/finance-billing-ops |
| electricity/gas procurement, tariffs | energy-procurement | ecc/energy-procurement |
| demand forecasting, multi-location retail | inventory-demand-planning | ecc/inventory-demand-planning |
| production scheduling, line balancing | production-scheduling | ecc/production-scheduling |
| QC non-conformance, FDA 21 CFR, CAPA | quality-nonconformance | ecc/quality-nonconformance |
| truckload/LTL carriers, FMCSA | carrier-relationship-management | ecc/carrier-relationship-management |
| freight exceptions, delays, damages | logistics-exception-management | ecc/logistics-exception-management |
| returns, RMA, disposition | returns-reverse-logistics | ecc/returns-reverse-logistics |
| HS/HTS tariff classification, customs | customs-trade-compliance | ecc/customs-trade-compliance |
| clinical decision support, drug interactions | healthcare-cdss-patterns | ecc/healthcare-cdss-patterns |
| EMR/EHR encounters, clinical safety | healthcare-emr-patterns | ecc/healthcare-emr-patterns |
| patient-safety eval harness | healthcare-eval-harness | ecc/healthcare-eval-harness |
| PHI/PII compliance patterns | healthcare-phi-compliance | ecc/healthcare-phi-compliance |
| HIPAA privacy/security entrypoint | hipaa-compliance | ecc/hipaa-compliance |
| master agreement drafting from template + JSON | master-agreement-generator | ecc/master-agreement-generator |
| e-signature field placement automation | esign-field-placement | ecc/esign-field-placement |
| visa document image translation | visa-doc-translate | ecc/visa-doc-translate |
| document OCR/convert/redact/sign (Nutrient) | nutrient-document-processing | ecc/nutrient-document-processing |
| software factory tasks/services vocabulary | software-factory | mattpocock/in-progress/software-factory |

### 10.11 Networking & homelab

| Trigger keywords | Skill | Path |
|---|---|---|
| Cisco IOS/IOS-XE config review | cisco-ios-patterns | ecc/cisco-ios-patterns |
| Netmiko SSH automation, TextFSM | netmiko-ssh-automation | ecc/netmiko-ssh-automation |
| BGP neighbor/route diagnostics | network-bgp-diagnostics | ecc/network-bgp-diagnostics |
| router/switch config pre-deploy validation | network-config-validation | ecc/network-config-validation |
| interface errors, CRC, duplex, flapping | network-interface-health | ecc/network-interface-health |
| homelab readiness checklist | homelab-network-readiness | ecc/homelab-network-readiness |
| home network gateways, APs, IP plan | homelab-network-setup | ecc/homelab-network-setup |
| Pi-hole, DoH, blocklists | homelab-pihole-dns | ecc/homelab-pihole-dns |
| VLAN segmentation IoT/guest/trusted | homelab-vlan-segmentation | ecc/homelab-vlan-segmentation |
| WireGuard VPN server/peers | homelab-wireguard-vpn | ecc/homelab-wireguard-vpn |

### 10.12 Web3, payments & markets

| Trigger keywords | Skill | Path |
|---|---|---|
| Solidity AMM/pool security | defi-amm-security | ecc/defi-amm-security |
| EVM token decimals mismatch | evm-token-decimals | ecc/evm-token-decimals |
| keccak256 vs sha3-256 in JS/TS | nodejs-keccak256 | ecc/nodejs-keccak256 |
| x402 agent payments, budgets | agent-payment-x402 | ecc/agent-payment-x402 |
| x402 service discovery, ERC-8004 (Roundhouse) | roundhouse-x402 | ecc/roundhouse-x402 |
| trading agent wallet/transaction security | llm-trading-agent-security | ecc/llm-trading-agent-security |
| prediction markets as oracle/data source | prediction-market-oracle-research | ecc/prediction-market-oracle-research |
| prediction-market/trading workflow risk review | prediction-market-risk-review | ecc/prediction-market-risk-review |
| Itô baskets, prediction-market data (read-only) | ito-baskets | ecc/ito-baskets |

### 10.13 Research & science

| Trigger keywords | Skill | Path |
|---|---|---|
| cited multi-source research reports | deep-research | ecc/deep-research |
| Exa neural web/code/company search | exa-search | ecc/exa-search |
| current-state research workflow | research-ops | ecc/research-ops |
| OpenAlex literature/DOI search | scientific-db-openalex-database | ecc/scientific-db-openalex-database |
| PubMed/NCBI E-utilities | scientific-db-pubmed-database | ecc/scientific-db-pubmed-database |
| USPTO patents/trademarks | scientific-db-uspto-database | ecc/scientific-db-uspto-database |
| gget genomics queries, BLAST | scientific-pkg-gget | ecc/scientific-pkg-gget |
| systematic literature review | scientific-thinking-literature-review | ecc/scientific-thinking-literature-review |
| evaluate papers/proposals | scientific-thinking-scholar-evaluation | ecc/scientific-thinking-scholar-evaluation |
| OSINT from sparse clues | osint-investigation | ecc/osint-investigation |
| primary-source research to markdown | research | mattpocock/engineering/research |

### 10.14 Agents, harness & ECC meta (details in `agents-context.md`)

| Trigger keywords | Skill | Path |
|---|---|---|
| compare coding agents head-to-head | agent-eval | ecc/agent-eval |
| agent self-debugging after failure | agent-introspection-debugging | ecc/agent-introspection-debugging |
| local agent API + tunnel + sandbox callback smoke test | agent-runtime-gateway-smoke-test | ecc/agent-runtime-gateway-smoke-test |
| self-rate output on 5 axes | agent-self-evaluation | ecc/agent-self-evaluation |
| trim ECC install to repo needs | agent-sort | ecc/agent-sort |
| eval-first agentic engineering | agentic-engineering | ecc/agentic-engineering |
| multi-agent OS on Claude Code | agentic-os | ecc/agentic-os |
| team operating model with AI-written code | ai-first-engineering | ecc/ai-first-engineering |
| autonomous agent with memory/schedules | autonomous-agent-harness | ecc/autonomous-agent-harness |
| autonomous loop architectures | autonomous-loops | ecc/autonomous-loops |
| continuous loop with quality gates | continuous-agent-loop | ecc/continuous-agent-loop |
| legacy v1 skill extractor (deprecated) | continuous-learning | ecc/continuous-learning |
| instinct-based learning via hooks | continuous-learning-v2 | ecc/continuous-learning-v2 |
| dmux tmux multi-agent panes | dmux-workflows | ecc/dmux-workflows |
| Claude DevFleet orchestration | devfleet | ecc/devfleet |
| task-local harnesses, eval gates | dynamic-workflow-mode | ecc/dynamic-workflow-mode |
| generator-evaluator (GAN-style) harness | gan-style-harness | ecc/gan-style-harness |
| progressive context retrieval for subagents | iterative-retrieval | ecc/iterative-retrieval |
| review an agent loop for failure modes | loop-design-check | ecc/loop-design-check |
| NanoClaw REPL sessions | nanoclaw-repl | ecc/nanoclaw-repl |
| dependency-graph parallel lanes | parallel-execution-optimizer | ecc/parallel-execution-optimizer |
| agent squads with owners/scope | team-agent-orchestration | ecc/team-agent-orchestration |
| pick agent personas for a team | team-builder | ecc/team-builder |
| multi-persona dev team session | dev-team | ecc/dev-team |
| shared memory/handoffs across Claude/Codex/Cursor | unified-memory | ecc/unified-memory |
| per-project memory /ck commands | ck | ecc/ck |
| live context meter checks | context-budget | ecc/context-budget |
| when to compact context | strategic-compact | ecc/strategic-compact |
| choose response depth by token estimate | token-budget-advisor | ecc/token-budget-advisor |
| token usage stat card | token-card | ecc/token-card |
| Claude Code token/spend tracking | cost-tracking | ecc/cost-tracking |
| ECC Tools burn/billing audit | ecc-tools-cost-audit | ecc/ecc-tools-cost-audit |
| long-lived/cloud agent ops controls | enterprise-agent-ops | ecc/enterprise-agent-ops |
| four-voice council for decisions | council | ecc/council |
| add external Codex critique to council | council-multi-model | ecc/council-multi-model |
| two-reviewer adversarial gate | santa-method | ecc/santa-method |
| recursive rollouts with decision ledger | recursive-decision-ledger | ecc/recursive-decision-ledger |
| plan document → executable steps | plan-orchestrate | ecc/plan-orchestrate |
| RFC → multi-agent DAG | ralphinho-rfc-pipeline | ecc/ralphinho-rfc-pipeline |
| orchestrate new feature end to end | orch-add-feature | ecc/orch-add-feature |
| orchestrate MVP from spec | orch-build-mvp | ecc/orch-build-mvp |
| orchestrate behavior change to a feature | orch-change-feature | ecc/orch-change-feature |
| orchestrate bug fix via regression test | orch-fix-defect | ecc/orch-fix-defect |
| shared orch Research-Plan-Implement engine | orch-pipeline | ecc/orch-pipeline |
| orchestrate behavior-preserving refactor | orch-refine-code | ecc/orch-refine-code |
| hookify rule files | hookify-rules | ecc/hookify-rules |
| fact-forcing PreToolUse gate | gateguard | ecc/gateguard |
| stop hook blocking unfinished work | delivery-gate | ecc/delivery-gate |
| write-time lint/format hooks (Plankton) | plankton-code-quality | ecc/plankton-code-quality |
| ~/.claude config garbage collection | config-gc | ecc/config-gc |
| config drift/integrity monitoring | config-health | ecc/config-health |
| ECC setup wizard | configure-ecc | ecc/configure-ecc |
| questions about ECC itself | ecc-guide | ecc/ecc-guide |
| map a workflow to ECC commands | ecc-recipes | ecc/ecc-recipes |
| prepare ECC skill contribution | ecc-contribution-review | ecc/ecc-contribution-review |
| ECC on DeepSeek Harness | deepseek-harness-setup | ecc/deepseek-harness-setup |
| Hermes workflows → sanitized ECC skills | hermes-imports | ecc/hermes-imports |
| are skills/rules actually followed | skill-comply | ecc/skill-comply |
| lint skills for Codex/Cursor compatibility | skill-host-compat | ecc/skill-host-compat |
| search existing skills before creating | skill-scout | ecc/skill-scout |
| audit skill quality | skill-stocktake | ecc/skill-stocktake |
| distill rules from skills | rules-distill | ecc/rules-distill |
| audit repo/MCP/plugin/env surface | workspace-surface-audit | ecc/workspace-surface-audit |
| automation inventory/overlap audit | automation-audit-ops | ecc/automation-audit-ops |

### 10.15 Process skills in ECC (details in sibling playbooks)

| Trigger keywords | Skill | Path | Playbook |
|---|---|---|---|
| one-line objective → multi-session plan | blueprint | ecc/blueprint | planning |
| PRD → implementation-ready capability | product-capability | ecc/product-capability | planning |
| validate the why, product diagnostics | product-lens | ecc/product-lens | planning |
| ambiguous high-impact change → scoped intent | intent-driven-development | ecc/intent-driven-development | planning |
| epic → story → sprint loop | story-lifecycle | ecc/story-lifecycle | planning |
| annotate plans in browser canvas | plan-canvas | ecc/plan-canvas | planning |
| impact analysis before change | change-impact | ecc/change-impact | planning |
| search packages/skills before coding | search-first | ecc/search-first | planning |
| CONTEXT.md domain context governance | context-and-decisions | ecc/context-and-decisions | planning |
| ADR files with alternatives/consequences | architecture-decision-records | ecc/architecture-decision-records | planning |
| module-local agent instructions/ownership | module-governance | ecc/module-governance | planning |
| route documentation governance | docs-governance | ecc/docs-governance | planning |
| keep long-lived docs from rotting | living-docs-governance | ecc/living-docs-governance | planning |
| onboarding guide for unfamiliar codebase | codebase-onboarding | ecc/codebase-onboarding | planning |
| CodeTour walkthroughs | code-tour | ecc/code-tour | planning |
| retroactive process audit of a project slice | brownfield-retrospective | ecc/brownfield-retrospective | review-quality |
| growth log of reusable patterns | growth-log | ecc/growth-log | review-quality |
| match legacy style, prevent drift | inherit-legacy-style | ecc/inherit-legacy-style | review-quality |
| CodeScene code health MCP | codehealth-mcp | ecc/codehealth-mcp | review-quality |
| review a GitHub issue | issue-review | ecc/issue-review | review-quality |
| TDD red-green-refactor | tdd-workflow | ecc/tdd-workflow | tdd-testing |
| Playwright E2E, POM | e2e-testing | ecc/e2e-testing | tdd-testing |
| post-deploy browser UI verification | browser-qa | ecc/browser-qa | tdd-testing |
| trace every button's state changes | click-path-audit | ecc/click-path-audit | tdd-testing |
| six-phase session verification | verification-loop | ecc/verification-loop | tdd-testing |
| test inventory, TEST-IDs, gap analysis | test-collaboration | ecc/test-collaboration | tdd-testing |
| cross-module regression ledger | module-regression | ecc/module-regression | tdd-testing |
| git branching, commits, history | git-workflow | ecc/git-workflow | git-shipping |
| Conventional Commit message review | conventional-commit-review | ecc/conventional-commit-review | git-shipping |
| GitHub issues/PRs/automation | github-ops | ecc/github-ops | git-shipping |
| fork/sanitize private project for open source | opensource-pipeline | ecc/opensource-pipeline | git-shipping |
| GitHub + Linear execution flow | project-flow-ops | ecc/project-flow-ops | git-shipping |
| Jira tickets read/update | jira-integration | ecc/jira-integration | git-shipping |

### 10.16 Non-ECC skills covered by sibling playbooks (index only)

- **planning.md**: addyosmani/{spec-driven-development, planning-and-task-breakdown, idea-refine, interview-me, incremental-implementation, documentation-and-adrs, deprecation-and-migration, constraint-driven-development, source-driven-development}; superpowers/{brainstorming, writing-plans, executing-plans}; mattpocock/engineering/{to-spec, to-tickets, wayfinder, prototype, grill-with-docs, implement, implement-spec, wizard, triage, ask-matt}; mattpocock/productivity/{grill-me, grilling, to-questionnaire, teach, wait-what}; mattpocock/in-progress/loop-me.
- **tdd-testing.md**: addyosmani/{test-driven-development, browser-testing-with-devtools}; superpowers/{test-driven-development, verification-before-completion}; mattpocock/engineering/tdd.
- **debugging.md**: addyosmani/debugging-and-error-recovery; superpowers/{systematic-debugging, diagnosing-superpowers}; mattpocock/engineering/diagnosing-bugs.
- **review-quality.md**: addyosmani/{code-review-and-quality, code-simplification, doubt-driven-development}; superpowers/{requesting-code-review, receiving-code-review}; mattpocock/engineering/{code-review, retro}; ponytail/{ponytail, ponytail-audit, ponytail-review, ponytail-debt, ponytail-gain, ponytail-help}; karpathy/karpathy-guidelines.
- **git-shipping.md**: addyosmani/{git-workflow-and-versioning, ci-cd-and-automation, shipping-and-launch}; superpowers/{finishing-a-development-branch, using-git-worktrees}; mattpocock/engineering/pr.
- **agents-context.md**: addyosmani/{context-engineering, using-agent-skills}; superpowers/{using-superpowers, dispatching-parallel-agents, subagent-driven-development, writing-skills}; mattpocock/productivity/{handoff, writing-for-agents}; mattpocock/in-progress/{chief-of-staff, claude-handoff}; mattpocock/engineering/setup-matt-pocock-skills (repo setup: issue tracker, triage labels, domain doc layout).
- **this playbook (sections 1–8)**: addyosmani/{api-and-interface-design, security-and-hardening, performance-optimization, frontend-ui-engineering, accessibility-engineering, observability-and-instrumentation}; mattpocock/engineering/{codebase-design, improve-codebase-architecture, domain-modeling}.

All paths above verified to exist under `library/` (each holds `SKILL_SOURCE.md`).
