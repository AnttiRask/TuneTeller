# TuneTeller — Refactor Plan

> Bring TuneTeller in line with how FillariStatus is built (`fillaristatus-plan.md`): small focused files, all config and text in one place, an API layer that never throws, tests with mocked HTTP, security headers, and automatic keyless deploys.
>
> **For Claude Code:** read this whole file first. Every change is checked with the user before it is committed, pushed or deployed. Phase 1 is app code only; Phase 2 touches cloud resources and each step needs approval. Never print secrets (see §8).

*Written: 2026-10-18.*

---

## 0. Status at a glance

| # | Item | Status |
|---|---|---|
| 0 | Fix: `spotifyr` sent the token in the URL, Spotify answered 401 (replaced by `httr2`, `app/www/spotify.R`, `4f3b123`) | **Done, live** (revision `tuneteller-app-00011-zpc`) |
| 1 | Phase 1: app code (structure, robustness, model switch, tests, security headers, light mode, footer, dependencies) | **Done, live** (commits `f4d57dc`, `7cd7ca3`, `5b63e98`; revision `tuneteller-app-00012-f64`, 100 % of traffic). Verified: 166 test expectations; the production image built from the lock (R 4.5.0, shiny 1.10.0, bslib 0.9.0) and checked in Chrome; the live site with a real prompt, logs clean |
| 2 | Phase 2: infrastructure. Decided: **stay in `tuneteller-app`**, new WIF pool, order below. Done so far: (a) the two stray failed services in `tuneteller-app` deleted (real BiblioStatus and Gallery services verified healthy first); (b) `tuneteller-runtime` service account with `secretAccessor` on the 3 secrets only, and the service switched to it (revision `tuneteller-app-00013-hqz`, verified with a real prompt, logs clean). (c) `roles/editor` removed from the compute account (it keeps `cloudbuild.builds.builder`); a test deploy afterwards built fine (Cloud Build SUCCESS, revision `tuneteller-app-00014-4kv`, still `tuneteller-runtime`, logs clean). (d) WIF pool `tuneteller` + provider `github-oidc` (only `AnttiRask/TuneTeller` on `refs/heads/main`) and the `tuneteller-deploy` account, **tested by a real source deploy and by negative tests** (§5.2); (e) websocket fix deployed (timeout 3600, session affinity, `allowReconnect`; revision `tuneteller-app-00016-glg`); (f) light/dark switch replaced (own button). **Next:** the GitHub Actions workflow (uses the account), complete `renv.lock` + `rocker/r-ver` Dockerfile, Dependabot and repo hygiene, image cleanup; TrackTeller/Gallery websocket fix (blocked, needs the user).

## 1. Why

- **The app broke silently** and was only noticed by hand: Spotify rejected `spotifyr`'s token handling, and an unhandled error then ended the whole session.
- **Deadline: GPT-4o mini is retired on 2027-01-14** (OpenAI notice; the API reports `shutdown_date: 2027-01-14`). The model is hard-coded in `server.R`.
- **The parser is fragile.** It extracts the artist from `**bold**` on line one, but the prompt never asks for bold. In a test of 5 models × 3 prompts only gpt-4o-mini always did it (gpt-5.4-nano 2 of 3, the others 0 of 3), so a plain model swap would break the app.
- The app has no tests, no error states, no security headers and a manual deploy as the default compute account.

## 2. Decisions (from the user, 2026-10-18)

| Question | Decision |
|---|---|
| OpenAI model | Try **gpt-5.4-nano** with JSON output and reasoning off; fallback gpt-5.4-mini. Cost is negligible either way (~70 input + ~90 output tokens per recommendation, ~US$0.13 per 1,000), so no new provider (Claude Haiku 5.5 would save ~8 cents per 1,000 but needs a new account and key) |
| Theme | **Dark stays the default**; add a light mode and a toggle |
| Footer | Add **FillariStatus** only; no source-repo link |
| Cooldown | **10 s** per session between recommendations |
| Order | Phase 1 first, reviewed with the user, then Phase 2 |
| GCP project (Phase 2) | Moving TuneTeller into the **BiblioStatus project** (`bibliostatus-app`) is acceptable if it makes sense, with its **own Workload Identity pool** (see §5) |

## 3. Phase 1 — app code (one deploy)

### 3.1 Structure
Target layout (mirrors FillariStatus §5):

```
app/
├── run.R            # entry point: port, security-headers wrapper
├── global.R         # libraries, sources www/*.R
├── ui.R             # theme, layout, footer (reads variables.R / strings.R)
├── server.R         # reactive logic only
└── www/
    ├── variables.R  # model, limits, cooldown, endpoints, brand colours, footer links
    ├── strings.R    # ALL user-facing text
    ├── prompt_versions.R  # prompt templates
    ├── api.R        # OpenAI + Spotify calls (never throw), state results
    ├── functions.R  # pure helpers (sanitise, build prompt, format followers)
    ├── security.R   # security headers + with_security_headers()
    └── styles.css
tests/testthat/
    ├── test-spotify.R (exists)  test-api.R  test-functions.R  test-security.R  test-server.R
```

### 3.2 Robustness
- `get_recommendation()` returns `list(data, error)` and never throws: timeout (`req_timeout`), retries for transient errors (`req_retry`), non-200, empty or malformed output → plain message in the UI, never raw error text.
- **Structured output:** ask the model for JSON (`artist`, `description`, `reason`) using the Responses API `text.format` JSON schema, and delete the regex parsing. Test this on gpt-5.4-nano first; fall back to gpt-5.4-mini if it is unreliable. Models in the GPT-5.4 family reject `temperature` and `reasoning: minimal`; use `reasoning: {effort: "none"}`.
- State machine for the card: `idle` / `ok` / `error` (OpenAI failed) / `not_found` (no Spotify match or no image).
- Remove debug `print()` calls and the `Sys.sleep(1)`.
- Keep the 190-character limit, enforced server-side too (not only in the browser).

### 3.3 Cost protection
- 10 s per-session cooldown after a request (button disabled with a notice while it applies).
- Request timeout so a hung upstream call cannot pin a session.

### 3.4 Model switch
- Model name in `variables.R`. Compare gpt-5.4-nano and gpt-5.4-mini side by side on a handful of prompts (quality of the pick, latency) before choosing, with the user.

### 3.5 Theme and footer
- Keep the current brand look (red `#C1272D`, Spotify green, background `#191414`, Gotham), **dark by default**, with a light mode and a toggle (first with `bslib::input_dark_mode()`; replaced by our own button because bslib's icon always shows the *current* mode and can't be restyled, and the user wants the icon of the mode a click switches to: sun while dark, moon while light); CSS custom properties so colours live in one place; check contrast in both modes (brand red is only 3.1:1 on `#191414`; FillariStatus uses `#F26B70` for dark-mode links).
- Footer: one shared list in `variables.R`; add **FillariStatus** (`https://fillaristatus.youcanbeapirate.com`). Keep the standard cross-app format.

### 3.6 Security
- `www/security.R` + `run.R` wrapper (wrap `app$httpHandler`; `shiny.http.response.filter` does nothing): `X-Frame-Options: DENY`, CSP `frame-ancestors 'none'` etc., `Referrer-Policy`, `Permissions-Policy`, HSTS, `nosniff`, plus a report-only full CSP (Spotify image host `i.scdn.co`, the font host).
- Escape everything from the model and from Spotify before it reaches the page (names, descriptions, URLs); only allow `https://` image and profile URLs.

### 3.7 Dependencies
- **Done:** `renv.lock` lost `shinyBS`, `spotifyr`, `dplyr` and their orphans (13 packages; a pure 200-line deletion).
- **Finding for Phase 2:** the lock is **not self-contained**. Packages required by locked ones (`commonmark`, `xtable`, `crayon`, `rappdirs`) have no entry; the current image works only because the `rocker/shiny` base image ships them. Moving to `rocker/r-ver` (as FillariStatus) needs a complete lock, i.e. `renv::restore()` + `renv::snapshot()` on R 4.5.
- Original plan:
- Drop `shinyBS` (used for a single alert) and, in `renv.lock`, `spotifyr` and its orphans (`janitor`, `snakecase`, `assertthat`, and `httr` if nothing else needs it). Needs `renv::restore()` first so `renv::snapshot()` can run; verify the Docker build afterwards.

### 3.8 Tests
- `testthat` 3 with `httr2::local_mocked_responses()`, no live calls. Cover: OpenAI parsing (valid JSON, malformed, empty, non-200, timeout), Spotify (done), prompt building, sanitising, cooldown, state machine via `testServer()`, security headers.
- Real-browser check (Chrome) before the deploy: dark and light, a real recommendation, the error state, the cooldown.

## 4. Open questions / observations for Phase 1
- The 4 recommendations seen in 90 days of logs all failed at Spotify, so the app has had no working traffic for a long time; nothing to migrate.
- Spotify's search fuzzy-matches nonsense names to some artist; acceptable (as before).
- The `/robots.txt`, `/.env`, `/sitemaps.xml` 404s in the logs are bot scans; nothing to do (`.env` is not in the image; check `.dockerignore` in Phase 2).

## 5. Phase 2 — infrastructure (each step needs approval)

### 5.1 Inventory and the move question (read-only inventory done 2026-10-18)

**`tuneteller-app` (project number 658789231217), as it is now**
- One real service, `tuneteller-app` (revision 00012, 1 CPU / 1 GiB, timeout 300 s (raised to 3600 s with session affinity and `allowReconnect` on 2026-10-18, see §6), concurrency 80, max 20 instances, startup CPU boost, public), plus the domain mapping `tuneteller.youcanbeapirate.com` (Ready).
- Secrets: `openai-api-key`, `spotify-client-id`, `spotify-client-secret`. Runtime identity: the **default compute account**, which also holds **`roles/editor`** (and `cloudbuild.builds.builder`). Owner: the user. No WIF pool, no dedicated service accounts, no budget API enabled in this project.
- Artifact Registry `cloud-run-source-deploy`: ~1.7 GB, 9 images of the app (every deploy adds one; nothing cleans up). Buckets `run-sources-tuneteller-app-europe-north1` and `tuneteller-app_cloudbuild` (build sources, also never cleaned).
- Billing account `01022A-90DC69-4116A8`, the same as `bibliostatus-app` and `trackteller-app`.

**Stray failed services (the "not ready" mystery).** On 2026-02-12/13, apps were deployed into the wrong projects. They never became ready, serve no traffic, have no domain mappings and no requests in 30 days (so they cost nothing and break nothing), but they show as "not ready" and confuse every listing:

| Project | Stray service | Why it failed |
|---|---|---|
| `tuneteller-app` | `bibliostatus-app`, `gallery-of-the-day-app` | The Cloud Run service agent can't read the image in another project's registry |
| `bibliostatus-app` | `tuneteller-app`, `trackteller-app` | Permission denied on the secrets / Secret Manager API not enabled |
| `trackteller-app` | `bibliostatus-app` | Same pattern |

The **real** TrackTeller (`trackteller-app` project, revision 00040) and TuneTeller (revision 00012) are healthy. This is what the FillariStatus plan means by "TrackTeller/TuneTeller show not ready". Deleting any of them needs the user's approval (each is in the project of another app).

**`bibliostatus-app` (for comparison):** WIF pool `github` with provider `github-oidc` restricted to the FillariStatus and BiblioStatus repos; service accounts `github-deploy` (broad: run.admin, storage.admin, artifactregistry.writer, builds.builder, serviceAccountUser, logging.viewer, all project-wide), `bibliostatus-runtime`, `fillaristatus-runtime`; secrets for Turso and Digitransit; the compute account has no Editor. **A failed stray `tuneteller-app` service already sits there, so moving would first need it deleted (same service name).**

**Move or stay?**

| | Stay in `tuneteller-app` | Move to `bibliostatus-app` |
|---|---|---|
| Work | New WIF pool + provider, `tuneteller-deploy` and `tuneteller-runtime` service accounts, drop Editor | The same, **plus** recreate 3 secrets (never printed), delete the stray service, new service, remap the domain, clean up and eventually delete the old project |
| Risk | None to the live app until the workflow is switched on | The domain mapping can only exist once: delete and recreate means a **certificate wait of ~15-30 min** (FillariStatus: 17 min) and a short outage, or a careful DNS-first dance |
| Benefit | Isolation (a leaked TuneTeller key or deploy account can't touch BiblioStatus or FillariStatus); matches TrackTeller and Gallery, which also have their own projects | One project to look at; shared budget/IAM overview (the billing account is already shared, so a billing-account budget already covers both) |

**Recommendation: stay.** Nothing the user asked for needs the move, and the move adds an outage window and a clean-up job. Isolation also argues for staying, because the shared `github-deploy` account in `bibliostatus-app` is broad. Either way a **new** pool is created, as requested.

**Decision pending from the user:** stay or move.

### 5.2 Identity and deploy (built and tested 2026-10-18)

**Runtime:** `tuneteller-runtime@tuneteller-app` (no project roles; `secretAccessor` on the 3 secrets only). The compute account lost `roles/editor` and keeps `cloudbuild.builds.builder`; a source deploy afterwards built fine.

**Keyless deploy identity (all in `tuneteller-app`):**
- Pool `tuneteller`, provider `github-oidc` (separate from BiblioStatus' `github` pool). Attribute condition: `assertion.repository == 'AnttiRask/TuneTeller' && assertion.ref == 'refs/heads/main'`; mapping `google.subject`, `attribute.repository`, `attribute.ref`. The STS API (`sts.googleapis.com`) had to be enabled.
- Service account `tuneteller-deploy@tuneteller-app`; only the principal set `.../workloadIdentityPools/tuneteller/attribute.repository/AnttiRask/TuneTeller` has `roles/iam.workloadIdentityUser` on it. (Nobody else can impersonate it; a temporary token-creator grant for testing was removed again.)
- Its permissions, narrowest that work: `roles/run.developer` **on the one service**; `roles/iam.serviceAccountUser` on `tuneteller-runtime` and on the compute account (the build identity), both resource-level; `roles/artifactregistry.writer` on the `cloud-run-source-deploy` repo; `roles/storage.objectAdmin` + `roles/storage.legacyBucketReader` on the `run-sources-tuneteller-app-europe-north1` bucket; project-level only `roles/cloudbuild.builds.editor` and the custom role `tunetellerBucketLister` (just `storage.buckets.list`: gcloud lists buckets to find its staging bucket; the built-in role with it, `storage.admin`, is far too broad).
- Found by testing: the first impersonated deploy failed with `storage.buckets.list denied`; the second (with the custom role) passed (revision `00017-6wn`, Cloud Build SUCCESS, still `tuneteller-runtime`, 3 secrets, logs clean).
- **Negative tests (all denied):** read a secret value, list secrets, change the service's IAM (public/private), grant itself a role, list service accounts, read the Cloud Build bucket, create another Cloud Run service. **Known and accepted:** `run.developer` includes `run.services.delete` on that one service. Someone who can run this account can already deploy arbitrary code (a bigger lever), so the real boundary is the repo's `main` branch (consider requiring pull requests / protecting `main`).
- Deploy command for the workflow (note: no `--allow-unauthenticated`, which needs IAM rights; the service is already public):
  `gcloud run deploy tuneteller-app --source . --project tuneteller-app --region europe-north1 --platform managed --service-account tuneteller-runtime@tuneteller-app.iam.gserviceaccount.com --set-secrets OPENAI_API_KEY=openai-api-key:latest --set-secrets SPOTIFY_CLIENT_ID=spotify-client-id:latest --set-secrets SPOTIFY_CLIENT_SECRET=spotify-client-secret:latest --memory 1Gi --timeout 3600 --session-affinity --quiet`
- Still to do: the workflow itself (pushes touching `app/**` or the build files: tests, then build + deploy + smoke test; actions pinned to SHAs; serialised runs; `GCP_PROJECT_ID` repo secret), which also tests the real GitHub-to-Google token exchange (impersonation only tested the permissions); `dependabot.yml`; repository hygiene (secret scanning, push protection, protected `main`).

### 5.3 Image and docs
- Dockerfile: pinned base image, non-root runtime user, renv cache disabled at build, system libraries from P3M sysreqs; allowlist `.dockerignore` so `.env` and other secrets can never end up in the image.
- Check Cloud Run `--concurrency` against the number of assets per page load (§6 gotcha), keep `--session-affinity`, a sensible `--max-instances`.
- Update `DEPLOY.md`, `README.md`, `CLAUDE.md` (and this plan).

## 6. Gotchas carried over from FillariStatus (relevant here)
- **Cloud Run `--timeout` caps the Shiny websocket too.** At the default 300 s the connection is closed after 5 minutes and the page greys out ("Disconnected from server"), which looks like the app "going to sleep". BiblioStatus fixed it on 2026-09-17 (`1d564aa`): `--timeout 3600`, `--session-affinity` and `session$allowReconnect(TRUE)`. TuneTeller, TrackTeller and Gallery of the Day had 300 s; TuneTeller got the fix on 2026-10-18. There is still no minimum instance anywhere, so the first visit after idle has a cold start of ~3 s.
- **Cloud Run concurrency must exceed the parallel asset requests of one page load**, otherwise overflow requests hit fresh instances that answer 404 for Shiny asset paths (blank page).
- **Shiny has no response-header hook**: wrap `httpHandler`.
- **`isTRUE(x)` can silently turn a feature off** (bslib's dark-mode input is a string, not a logical).
- **Browsers cache `styles.css`**: cache-bust with the file's mtime (evaluated at startup).
- **`mutate()` data masking**: don't name function arguments like data columns.
- **`testServer()` does not step `debounce()` timers** for a value already read.
- **GitHub/Google platform lag**: re-check status before concluding something failed.
- **Verify, don't assume**: after every push check the remote and the workflow run; after every deploy check the revision and use the live app with a real prompt.

## 7. Conventions
- R, tidyverse style (`|>` is fine; the existing code uses `%>%`, so match the file being edited), `httr2`, `renv`; config in `variables.R`, text in `strings.R`.
- Small commits, one concern each; after each push verify `git ls-remote origin refs/heads/main` equals `HEAD`.
- When something fails: read the full error, find the root cause, explain it, propose 2–3 ranked fixes, implement the top one; don't retry the same thing.
- Show the user the running app after every visible change.

## 8. Handling secrets
- Never `cat`/`grep` secret files or print env values; check lengths and HTTP status only. `.env` values are quoted (`KEY="value"`), so they must be unquoted before use in `curl`.
- Don't `source <(grep .env | sed export)`.
- Test scripts that call live APIs use the Secret Manager values through environment variables and print only results.

## 9. Test results behind the model decision (2026-10-18)

Prompt `prompt_ver2`, 3 prompts per model, `max_output_tokens` 2000, reasoning off (`minimal` for gpt-5-nano, `none` for gpt-5.4 models):

| Model | Latency | Bold name parsed | Tokens in / out |
|---|---|---|---|
| gpt-4o-mini | 1.7–2.4 s | 3/3 | ~70 / ~105 |
| gpt-4.1-nano | 1.1–1.7 s | 0/3 | ~70 / ~95 |
| gpt-5-nano | 1.2–1.4 s | 0/3 | ~69 / ~83 |
| gpt-5.4-nano | 1.3–1.6 s | 2/3 | ~69 / ~84 |
| gpt-5.4-mini | 1.3–1.5 s | 0/3 | ~69 / ~69 |

Prices (secondary sources, not verified on OpenAI's page): gpt-5.4-nano US$0.20 in / US$1.25 out per 1M tokens; gpt-5.4-mini US$0.75 / US$4.50; Claude Haiku 5.5 US$0.10 / US$0.50. Not yet measured: JSON-schema reliability and quality of the artist picks.
