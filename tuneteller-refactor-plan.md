# TuneTeller — Refactor Plan

> Bring TuneTeller in line with how FillariStatus is built (`fillaristatus-plan.md`): small focused files, all config and text in one place, an API layer that never throws, tests with mocked HTTP, security headers, and automatic keyless deploys.
>
> **For Claude Code:** read this whole file first. Every change is checked with the user before it is committed, pushed or deployed. Phase 1 is app code only; Phase 2 touches cloud resources and each step needs approval. Never print secrets (see §8).

*Written 2026-10-18; last updated 2026-11-02, after bringing TuneTeller up to the level of the other apps (§10). Phase 1 and Phase 2 are done and live.*

---

## 0. Status at a glance

Live: https://tuneteller.youcanbeapirate.com, Cloud Run service `tuneteller-app` in project `tuneteller-app` (revision `tuneteller-app-00025-h2r`, commit `e09bf9cd906b`, 100 % of traffic, `--max-instances 3`).

| # | What | Status |
|---|---|---|
| 0 | `spotifyr` sent the token in the URL and Spotify answered 401; replaced by `httr2` | **Done, live** (`4f3b123`) |
| 1 | Phase 1, app code: structure, never-throwing API layer, gpt-5.4-nano with JSON output, 10 s cooldown, security headers, light mode, FillariStatus in the footer, tests | **Done, live** (`f4d57dc`, `7cd7ca3`, `5b63e98`); 166 test expectations then, 189 now (api 30, functions 70, security 31, server 26, ui 32) |
| 2a | Dedicated runtime account `tuneteller-runtime` (3 secrets only); `roles/editor` removed from the compute account | **Done, live**; builds verified afterwards |
| 2b | Keyless deploys: WIF pool `tuneteller`, provider `github-oidc` (this repo, `main` only), account `tuneteller-deploy` (§5.2) | **Done**; tested by impersonation, negative tests, and real workflow runs |
| 2c | GitHub Actions: tests, then deploy + smoke test (checks the `git-sha` label); Dependabot | **Done, live** (first push-triggered run `39149036071`) |
| 2d | Complete `renv.lock` (41 packages, R 4.6.1), `rocker/r-ver:4.6.1` non-root image (1.85 GB), allowlist `.dockerignore` | **Done, live** (revision `00019-j79`) |
| 2e | Repo hygiene: secret scanning, push protection, Dependabot security updates, `main` protected (no force-push or deletion, enforced for admins) | **Done**, read back |
| 2f | Cleanup: Artifact Registry policy (since 2026-11-02 the siblings' rule, in `infra/`: keep the 5 newest, delete older than 14 days); 30-day lifecycle on the two build buckets; two stray failed services deleted | **Done**; the cleanup ran (20 versions on 2026-10-18, 5 on 2026-11-02) |
| 2g | Three Dependabot PRs (`auth` 3, `setup-gcloud` 3, `checkout` 7) merged one at a time, each followed by a deploy and a check | **Done** (`00020`-`00022`) |
| 2h | Websocket: `--timeout 3600` and `--session-affinity` | **Done, live**. `session$allowReconnect(TRUE)` was added too but **does nothing** on Cloud Run (§6) |
| 2i | Polish: the CSP is **enforced** (promoted from report-only, `'unsafe-eval'` dropped, Spotify image hosts widened to `*.scdn.co`); `--max-instances 3` (was 20); dark text on the Spotify button (7.1:1, was 2.6:1); palette notes moved from `www/` to `design/`; the tests run on the packages in `renv.lock` (R 4.6.1); README screenshot and project page refreshed | **Done and verified live** (revision `00024-2x5`; §10) |
| 2j | Parity with the other apps (§10): the six R files are no longer public (`scripts/`, not `www/`); `GET /health` (200 `ok` / 503 naming what is misconfigured) checked by the deploy smoke test; uptime check on `/health` every 5 minutes plus an email alert; the cleanup policy and the alert script in `infra/`; a "Your session has ended" dialog with a Reload button | **Done and verified live** (revision `00025-h2r`; the uptime check passed from all six probe locations: see §10) |

Related work in the sibling apps, done in the same session: the light/dark switch now shows the mode a click switches to in TuneTeller and FillariStatus (own button instead of bslib's, which can't be restyled); `allowReconnect("force")` in FillariStatus and BiblioStatus, plus a fix in BiblioStatus that restores the committed filters after a reconnect (details in their `CLAUDE.md` files).

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
├── run.R            # entry point: port, /health and the security headers around the app
├── global.R         # libraries, sources scripts/*.R
├── ui.R             # theme, layout, footer (reads variables.R / strings.R)
├── server.R         # reactive logic only
├── scripts/         # R code. NEVER in www/: everything in www/ is served to the browser
│   ├── variables.R  # model, limits, cooldown, endpoints, brand colours, footer links
│   ├── strings.R    # ALL user-facing text
│   ├── prompt_versions.R  # prompt templates
│   ├── api.R        # OpenAI + Spotify calls (never throw), state results
│   ├── functions.R  # pure helpers (sanitise, build prompt, format followers, artist card)
│   ├── health.R     # GET /health
│   └── security.R   # security headers + with_security_headers()
└── www/             # served as it is: styles.css, mode-toggle.js, cooldown.js, session-ended.js, images
tests/testthat/
    ├── test-api.R  test-functions.R  test-health.R  test-security.R  test-server.R  test-ui.R
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
- `scripts/security.R` + `run.R` wrapper (wrap `app$httpHandler`; `shiny.http.response.filter` does nothing): `X-Frame-Options: DENY`, CSP (report-only at first, **enforced since 2026-10-18**: `default-src 'self'`, inline script/style allowed, no `unsafe-eval`, Spotify's image CDNs, the font host, `wss:`), `Referrer-Policy`, `Permissions-Policy`, HSTS, `nosniff`, plus a report-only full CSP (Spotify image host `i.scdn.co`, the font host).
- Escape everything from the model and from Spotify before it reaches the page (names, descriptions, URLs); only allow `https://` image and profile URLs.

### 3.7 Dependencies
- **Done:** `renv.lock` lost `shinyBS`, `spotifyr`, `dplyr` and their orphans (13 packages; a pure 200-line deletion).
- **Resolved (Phase 2):** the old lock was not self-contained (packages required by locked ones, such as `commonmark`, `xtable`, `crayon` and `rappdirs`, had no entry; the old image worked only because `rocker/shiny` ships them). The new lock was generated inside `rocker/r-ver:4.6.1` (see 5.3), so the dependency closure is complete.
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

**`tuneteller-app` (project number 658789231217), as it was found on 2026-10-18 (before Phase 2; everything listed as missing here has since been done, see §0)**
- One real service, `tuneteller-app` (revision 00012, 1 CPU / 1 GiB, timeout 300 s (raised to 3600 s with session affinity on 2026-10-18, see §6; the `allowReconnect(TRUE)` line added at the same time has no effect), concurrency 80, max 20 instances, startup CPU boost, public), plus the domain mapping `tuneteller.youcanbeapirate.com` (Ready).
- Secrets: `openai-api-key`, `spotify-client-id`, `spotify-client-secret`. Runtime identity: the **default compute account**, which also holds **`roles/editor`** (and `cloudbuild.builds.builder`). Owner: the user. No WIF pool, no dedicated service accounts, no budget API enabled in this project.
- Artifact Registry `cloud-run-source-deploy`: ~1.7 GB, 9 images of the app (every deploy adds one; nothing cleans up). Buckets `run-sources-tuneteller-app-europe-north1` and `tuneteller-app_cloudbuild` (build sources, also never cleaned).
- Billing account `01022A-90DC69-4116A8`, the same as `bibliostatus-app` and `trackteller-app`.

**Stray failed services (the "not ready" mystery).** On 2026-02-12/13, apps were deployed into the wrong projects. They never became ready, serve no traffic, have no domain mappings and no requests in 30 days (so they cost nothing and break nothing), but they show as "not ready" and confuse every listing:

| Project | Stray service | Why it failed |
|---|---|---|
| `tuneteller-app` | `bibliostatus-app`, `gallery-of-the-day-app` | The Cloud Run service agent can't read the image in another project's registry |
| `bibliostatus-app` | `tuneteller-app`, `trackteller-app` | Permission denied on the secrets / Secret Manager API not enabled |
| `trackteller-app` | `bibliostatus-app` | Same pattern |

The **real** TrackTeller (`trackteller-app` project, revision 00040) and TuneTeller (revision 00012) are healthy. This is what the FillariStatus plan means by "TrackTeller/TuneTeller show not ready". Deleting any of them needs the user's approval (each is in the project of another app). **Status 2026-11-07: all of them are gone.** The two in `tuneteller-app` were deleted earlier (row 2f), the one in `trackteller-app` on 2026-10-31, and the last two in `bibliostatus-app` (`trackteller-app`, `tuneteller-app`) on 2026-11-07 with the owner's approval, after checking again: no requests and no log entries in 30 days, no domain mapping, no reference to them in any repo. Their configurations were saved first. Each project now lists only its own app.

**`bibliostatus-app` (for comparison):** WIF pool `github` with provider `github-oidc` restricted to the FillariStatus and BiblioStatus repos; service accounts `github-deploy` (broad: run.admin, storage.admin, artifactregistry.writer, builds.builder, serviceAccountUser, logging.viewer, all project-wide), `bibliostatus-runtime`, `fillaristatus-runtime`; secrets for Turso and Digitransit; the compute account has no Editor. **A failed stray `tuneteller-app` service already sits there, so moving would first need it deleted (same service name).** **Since changed (2026-11-09):** `github-deploy` no longer exists; BiblioStatus and FillariStatus deploy with their own narrow accounts.

**Move or stay?**

| | Stay in `tuneteller-app` | Move to `bibliostatus-app` |
|---|---|---|
| Work | New WIF pool + provider, `tuneteller-deploy` and `tuneteller-runtime` service accounts, drop Editor | The same, **plus** recreate 3 secrets (never printed), delete the stray service, new service, remap the domain, clean up and eventually delete the old project |
| Risk | None to the live app until the workflow is switched on | The domain mapping can only exist once: delete and recreate means a **certificate wait of ~15-30 min** (FillariStatus: 17 min) and a short outage, or a careful DNS-first dance |
| Benefit | Isolation (a leaked TuneTeller key or deploy account can't touch BiblioStatus or FillariStatus); matches TrackTeller and Gallery, which also have their own projects | One project to look at; shared budget/IAM overview (the billing account is already shared, so a billing-account budget already covers both) |

**Recommendation: stay.** Nothing the user asked for needs the move, and the move adds an outage window and a clean-up job. Isolation also argues for staying, because the shared `github-deploy` account in `bibliostatus-app` is broad. Either way a **new** pool is created, as requested. **Since changed (2026-11-09):** `github-deploy` no longer exists; BiblioStatus and FillariStatus deploy with their own narrow accounts.

**Decided by the user (2026-10-18): stay.** A new pool was created, as requested.

### 5.2 Identity and deploy (built and tested 2026-10-18)

**Runtime:** `tuneteller-runtime@tuneteller-app` (no project roles; `secretAccessor` on the 3 secrets only). The compute account lost `roles/editor` and keeps `cloudbuild.builds.builder`; a source deploy afterwards built fine. **2026-11-07:** its leftover `secretAccessor` on the 3 secrets was removed too (with the owner's approval, old policies saved); new revisions of `tuneteller-app` started afterwards (a harmless label added and removed), so `tuneteller-runtime` alone is enough.

**Keyless deploy identity (all in `tuneteller-app`):**
- Pool `tuneteller`, provider `github-oidc` (separate from BiblioStatus' `github` pool). Attribute condition: `assertion.repository == 'AnttiRask/TuneTeller' && assertion.ref == 'refs/heads/main'`; mapping `google.subject`, `attribute.repository`, `attribute.ref`. The STS API (`sts.googleapis.com`) had to be enabled.
- Service account `tuneteller-deploy@tuneteller-app`; only the principal set `.../workloadIdentityPools/tuneteller/attribute.repository/AnttiRask/TuneTeller` has `roles/iam.workloadIdentityUser` on it. (Nobody else can impersonate it; a temporary token-creator grant for testing was removed again.)
- Its permissions, narrowest that work: `roles/run.developer` **on the one service**; `roles/iam.serviceAccountUser` on `tuneteller-runtime` and on the compute account (the build identity), both resource-level; `roles/artifactregistry.writer` on the `cloud-run-source-deploy` repo; `roles/storage.objectAdmin` + `roles/storage.legacyBucketReader` on the `run-sources-tuneteller-app-europe-north1` bucket; project-level only `roles/cloudbuild.builds.editor` and the custom role `tunetellerBucketLister` (just `storage.buckets.list`: gcloud lists buckets to find its staging bucket; the built-in role with it, `storage.admin`, is far too broad).
- Found by testing: the first impersonated deploy failed with `storage.buckets.list denied`; the second (with the custom role) passed (revision `00017-6wn`, Cloud Build SUCCESS, still `tuneteller-runtime`, 3 secrets, logs clean).
- **Negative tests (all denied):** read a secret value, list secrets, change the service's IAM (public/private), grant itself a role, list service accounts, read the Cloud Build bucket, create another Cloud Run service. **Known and accepted:** `run.developer` includes `run.services.delete` on that one service. Someone who can run this account can already deploy arbitrary code (a bigger lever), so the real boundary is the repo's `main` branch (consider requiring pull requests / protecting `main`).
- Deploy command for the workflow (note: no `--allow-unauthenticated`, which needs IAM rights; the service is already public):
  `gcloud run deploy tuneteller-app --source . --project tuneteller-app --region europe-north1 --platform managed --service-account tuneteller-runtime@tuneteller-app.iam.gserviceaccount.com --set-secrets OPENAI_API_KEY=openai-api-key:latest --set-secrets SPOTIFY_CLIENT_ID=spotify-client-id:latest --set-secrets SPOTIFY_CLIENT_SECRET=spotify-client-secret:latest --memory 1Gi --timeout 3600 --session-affinity --quiet`
- Done afterwards: the workflows (`.github/workflows/tests.yml`, `deploy_shiny_app.yml`), `dependabot.yml` and the repository hygiene settings; the real GitHub-to-Google token exchange was proved by workflow run `39146179058` (impersonation had only tested the permissions). No GitHub secret is used: the project id and number are in the workflow's `env`.

### 5.3 Image and docs (done and deployed 2026-10-18)

- **Dockerfile:** `rocker/r-ver:4.6.1` (not `rocker/shiny`), system libraries from Posit's sysreqs API for the dependency closure (`cmake make libcurl4-openssl-dev libicu-dev libssl-dev libuv1-dev zlib1g-dev`), `renv::restore()` from Posit's Linux binaries (nothing compiled), renv cache and sandbox disabled, non-root user `tuneteller`, `CMD Rscript app/run.R` (`SHINY_ENV` was unused and is gone). Same design as FillariStatus.
- **`.dockerignore`:** an allowlist (`app`, `renv.lock`, `.Rprofile`, `renv/activate.R`, `renv/settings.json`), plus never `.Renviron`, `secret.R`, `.env`, `app_cache`. Checked inside the running image.
- **`docker-compose.yml`:** the app is mounted at `/app/app`; still http://localhost:8081.
- **Regenerating `renv.lock`** (needed when the app uses a new package): the old lock was incomplete and a lock made on a laptop can contain broken installs, so generate it in the target image. Install the direct packages (`bslib httr2 jsonlite purrr shiny shinycssloaders stringr`) into a clean library inside `rocker/r-ver:4.6.1` with the Posit Linux binary repo and a `HTTPUserAgent` naming the platform (otherwise Posit serves source and `sass` compiles for minutes), install `renv` 1.0.11 (the version `renv/activate.R` pins) from the CRAN archive, then `renv::snapshot(library = <clean lib>, packages = c(<direct>, "renv"), lockfile = ..., force = TRUE)`, and `docker cp` the file out. **Check** that every `Requirements` entry in the lock is itself in the lock (a laptop run silently dropped `stringi` and `vctrs`, which failed to compile).
- **Docker Desktop (Rancher) can't bind-mount `/tmp`:** use `docker cp`, or mount from under the home directory.
- **zsh doesn't word-split unquoted variables:** building a URL with a `for p in $PKGS` loop silently sent one giant `pkgname`; build such requests in Python.
- Done afterwards: the Artifact Registry cleanup policy, the bucket lifecycle rules and the repository hygiene (§0, row 2e and 2f). The user's go on the other two apps is still open (§10).

## 6. Gotchas carried over from FillariStatus (relevant here)
- **Cloud Run `--timeout` caps the Shiny websocket too.** At the default 300 s the connection is closed after 5 minutes and the page greys out ("Disconnected from server"), which looks like the app "going to sleep". BiblioStatus fixed it on 2026-09-17 (`1d564aa`): `--timeout 3600`, `--session-affinity` and `session$allowReconnect(TRUE)`. **Only the timeout does anything:** `allowReconnect(TRUE)` is inert on Cloud Run (the client reconnects only if the host, such as Shiny Server or Posit Connect, allows it too; checked by closing the socket in the browser, locally and on the live TuneTeller: the page stays greyed out). `allowReconnect("force")` does reconnect (a new session, inputs re-sent; about 1.5 s, tested on FillariStatus and BiblioStatus, which now use it), but it is unsafe for TuneTeller: the re-sent "Get Recommendation" click count would run `recommendation_result` again and make a paid OpenAI call. Make that observer idempotent before ever using `"force"` here; until then a page open for over an hour greys out until reloaded. TuneTeller, TrackTeller and Gallery of the Day had 300 s; TuneTeller got the fix on 2026-10-18. There is still no minimum instance anywhere, so the first visit after idle has a cold start of ~3 s.
- **Cloud Run concurrency must exceed the parallel asset requests of one page load**, otherwise overflow requests hit fresh instances that answer 404 for Shiny asset paths (blank page).
- **Shiny has no response-header hook**: wrap `httpHandler`.
- **`isTRUE(x)` can silently turn a feature off** (bslib's dark-mode input is a string, not a logical).
- **Browsers cache `styles.css`**: cache-bust with the file's mtime (evaluated at startup).
- **`mutate()` data masking**: don't name function arguments like data columns.
- **`testServer()` does not step `debounce()` timers** for a value already read.
- **GitHub/Google platform lag**: re-check status before concluding something failed.
- **Verify, don't assume**: after every push check the remote and the workflow run; after every deploy check the revision and use the live app with a real prompt.

- **Artifact Registry cleanup policy JSON:** the action is an object, `{"type": "Keep"}` / `{"type": "Delete"}`, and `tagState` is `"any"`; a bare string (`"Keep"`, `"KEEP"`) is rejected with `Invalid action`. A `Keep` policy wins over a `Delete` one. Policies run asynchronously (about daily), and rolling back to a revision whose image was removed no longer works.
- **Merge Dependabot action bumps one at a time and prove each one:** read the diff, check that the pinned SHA is the tag's commit (`gh api repos/<owner>/<repo>/git/matching-refs/tags/<tag>`), merge, then `gh workflow run deploy_shiny_app.yml --ref main` and check the run, the `git-sha` label on the service, HTTP 200 and the logs before the next one. The workflow files aren't in the deploy paths, so a merge alone proves nothing about the deploy.
- **`gh workflow run` from `main` is how to deploy without a code change.** The WIF provider only accepts `refs/heads/main`.
- **Testing a Content-Security-Policy:** (1) the Chrome console tool shows **no** CSP violations at all, neither report-only nor enforced; (2) a `securitypolicyviolation` listener only sees what happens after it is installed, so it misses everything at page load; (3) the tool's JavaScript runs outside the page's CSP and shims `eval` (`eval('1+1')` is "allowed" even when the policy forbids it): test from an inline `<script>` with `new Function(...)`. What works: run a throwaway copy of the app whose `ui.R` has a recorder as the **first** script in `<head>` (`window.__v = []; document.addEventListener('securitypolicyviolation', e => __v.push(...))`), use the app for real (a recommendation, both colour modes), then read `window.__v`. Prove the instrument first by loading a foreign image or script on purpose.
- **Screenshots with the Chrome tool:** `resize_window` does not change the viewport (it stayed 1174x771), so a tall page is cut off; scale the page instead (`document.body.style.zoom = 0.73`, `document.documentElement.style.overflow = 'hidden'`, scroll to the top). The mouse pointer is drawn into the saved image and moving it can land it on the content (the zoom skews its coordinates): leave it in empty space and crop it out (PIL is available; ImageMagick is not). Saved captures go to `/tmp/claude-chrome-screenshots-*`: delete them afterwards.
- **`git commit` commits everything staged, not just what you last `git add`ed.** A `git mv` done earlier was swept into an unrelated commit. Run `git diff --cached --stat` before every commit; if it already went wrong and nothing is pushed, `git reset <last pushed commit>` keeps the working tree and lets you redo the commits.
- **A Docker VM can't bind-mount `/tmp`** (Rancher Desktop) and **`docker build` output reports the pipe's exit code**; use `docker cp` and read the log's own last line.
- **R files in `www/` are public.** Shiny serves everything in `www/` as a static file, so `www/api.R` was one request away. Put R code in `scripts/` (or `R/`, which Shiny sources itself); `www/` is for what the browser needs. Check with `curl -s -o /dev/null -w '%{http_code}' https://<app>/<file>.R`.
- **`display: flex` beats the `hidden` attribute** (author CSS overrides the browser's `[hidden] { display: none }`): a hidden dialog styled with `display: flex` shows anyway. Add `#id[hidden] { display: none; }`.
- **Shiny's `shiny:disconnected` is a jQuery event:** a native `addEventListener` never receives it; use `$(document).on(...)` after `DOMContentLoaded`. Shiny's own grey layer is `#shiny-disconnected-overlay` (z-index 99998); a dialog must sit above it. Test by closing the socket (`Shiny.shinyapp.$socket.close()`), and test the false alarm too: a page that is unloading also drops the socket.
- **Health checks should read the environment, name what is wrong and never print values**, and must not call paid APIs. Test the 503 end to end with a deliberately broken instance (a quote-wrapped key, a non-hex id).
- **The scratch R library under `/tmp` does not survive a restart** (and R may have been upgraded): rebuild it from Posit's binaries (`HTTPUserAgent` set) before running the tests.
- **`sed 's/.../.../'` with a `/` in the replacement text breaks:** use another delimiter, or Python.
- **Don't `pkill -f` a pattern that appears in your own command line:** it kills the shell running it (exit 144).
- **A rule that denies edits to another app's deploy script** (the auto-mode classifier) is a signal to stop and ask, not to route around it.

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

## 10. What is left (2026-10-18)

Nothing is blocking: Phase 1 and Phase 2 are done and live, and so is the polish the user chose from the first version of this list. What remains is one check that has to wait, one thing only the user can do, and a few things decided against for now.

### Parity with the other apps (2026-11-02)

The user's comparison table (TrackTeller, BiblioStatus, Gallery of the Day, TuneTeller, FillariStatus) showed five rows where TuneTeller was behind. All five are done and verified on the live site:

| Row | Before | Now |
|---|---|---|
| R source files public | yes: `/api.R`, `/prompt_versions.R` (the model's instructions and JSON schema), `/variables.R`, `/security.R`, `/strings.R`, `/functions.R` all returned 200 | no: moved to `app/scripts/`; all six return 404 live (`www/` keeps only what the browser needs) |
| `/health` | 404 | 200 `ok` live; 503 `unhealthy: <names>` when a key is missing or malformed (a quote-wrapped key counts); calls neither OpenAI nor Spotify |
| Uptime check and alert | not set up | Cloud Monitoring check on `/health` every 5 minutes (HTTPS, body must be exactly `ok`), email alert when 2 or more locations fail, created by `infra/setup_uptime_alert.sh` (re-runnable: a second run reports `exists` for all three; the address is passed in, not stored). Read back from Google: check, policy (enabled, one channel) and email channel all as intended; first results `check_passed = True` from São Paulo and Iowa. Checked again on 2026-11-03 over the last 2 hours (Monitoring API): all six locations report and every check passed (usa-virginia 144/144, usa-oregon 144/144, usa-iowa 143/143, eur-belgium 144/144, apac-singapore 144/144, sa-brazil-sao_paulo 143/143); no alert fired. The alert path itself (a real failure emailing) has not been triggered |
| Registry cleanup policy in repo | no | `infra/artifact-registry-cleanup.json`, the same rule as the siblings (keep 5, delete older than 14 days), applied from the file |
| Message when the session ends | no | hidden `session_ended_dialog()` + `www/session-ended.js`: "Your session has ended" with a Reload button over Shiny's grey layer; not shown while the page unloads; never reloads by itself |

Rows that were already at par: security headers, CSP (enforced), tests in CI, deploy waits for tests, `git-sha` label. Test blocks: 53 then, 66 now (235 expectations); the other apps have 57-283.

Seen in TrackTeller and not in the table, not done: a `CSP_MODE` environment switch (enforce, report-only or off, no rebuild to go back) and a `/csp-report` endpoint that logs violations; its comment says its CSP needs `'unsafe-eval'` because shiny.min.js evals the outputs that carry scripts, which TuneTeller's outputs don't (tested: zero violations without it).

### Only the user can do
- **OpenAI usage limit.** Set a monthly limit in the OpenAI dashboard: the cooldown is per session, so a script that opens many sessions could still make many (cheap) calls. `--max-instances 3` already caps the capacity.
- ~~Billing budget.~~ **Done 2026-11-05.** The assumption was wrong: the EUR 30 budgets on the shared billing account cover `bibliostatus-app` only, so this project had none. The user created `tuneteller-app monthly` (EUR 10 a month, this project only, email at 50%, 90% and 100% of actual spend; read back) with `--billing-project` set to a project where the Billing Budgets API is enabled, so nothing was enabled in `tuneteller-app`.

### Decided against, for now (2026-10-18)
- **TrackTeller and Gallery of the Day websocket fix** (`--timeout 3600 --session-affinity`; both still have 300 s, so their pages grey out after 5 minutes): skipped; the user will come back to it. `allowReconnect(TRUE)` is pointless there; `"force"` needs a review of each app's server first (§6).
- **Cold start** (`min-instances` 0, about 3 s on the first visit after idle): no change.
- **Comparing gpt-5.4-nano with gpt-5.4-mini:** skipped. `openai_model` in `scripts/variables.R` is the one-line switch.
- **A page open for over an hour still greys out** (3600 s is Cloud Run's maximum and `allowReconnect(TRUE)` does nothing). `"force"` needs `recommendation_result` to be idempotent first (§6); not worth it for short sessions.
- **R package updates stay manual** (Dependabot doesn't cover renv): regenerate `renv.lock` inside the image as described in §5.3 when an update or a new package is needed.

### Done from the first version of this list (2026-10-18)
- **`--max-instances 3`** in `deploy.sh`, the workflow and `DEPLOY.md` (it was Cloud Run's default of 20).
- **CSP enforced.** One policy in `scripts/security.R`: `default-src 'self'`, inline script and style (Shiny and bslib need them), **no `unsafe-eval`**, images from `*.scdn.co` and `*.spotifycdn.com`, fonts from `fonts.cdnfonts.com`, `connect-src 'self' wss:`. Tested in a browser with a violation recorder running from the first script: **zero violations** across page load, a real recommendation (artist image, font, Spotify button) and both colour modes; a foreign image and script were blocked, as they should be (§6 for how to test this). Tests in `test-security.R`.
- **Spotify button contrast:** dark text (`#191414`) on the green, 7.1:1 (white was 2.6:1), and a brighter green on hover/focus, 9.5:1 (the old darker green was 4.3:1). The underline is gone too. Test in `test-ui.R`.
- **Palette notes** moved from `app/www/` (served publicly) to `design/youcanbeapirate_colors.txt`.
- **CI on the lock:** `tests.yml` now takes the R version from `renv.lock` (it was pinned to 4.5 while the image runs 4.6.1) and restores the locked packages with `setup-renv`; `testthat` and `withr` are installed on top without being recorded. Checked in the run log: R 4.6.1, shiny 1.14.0, bslib 0.12.0, httr2 1.3.0, shinycssloaders 1.1.0, all as binaries; 1 min 43 s.
- **Verified in production** after the deploy (revision `00024-2x5`): a real recommendation with the artist image from `*.scdn.co` under the enforced CSP, the Spotify button measured at 7.05:1 in both colour modes, and zero violations from a listener installed after load (the load itself was proved clean locally with the early recorder). The project page serves the new text and a screenshot byte-identical to the repo's.
- **README screenshot and project page:** a new screenshot of a real recommendation in the new design (`img/` and `docs/`); the page no longer names GPT-4o-mini, says "Dark and Light", and has FillariStatus in the footer.

### Known and accepted
- Only desktop Chrome was driven. **Phones, Safari and Firefox were never checked**, including the new light/dark button, the cooldown countdown and the enforced CSP.
- `run.developer` lets the deploy account delete the one service (§5.2); the real boundary is the repo's `main` branch.
- The branch-protection enforcement was read back but never exercised (testing it would mean rewriting `main`).
- Cloud Build still runs as the default compute account, which keeps `cloudbuild.builds.builder`.
- Spotify's search fuzzy-matches nonsense names to some artist.
