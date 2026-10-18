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
| 1 | Phase 1: app code (structure, robustness, model switch, tests, security headers, light mode, footer, dependencies) | **Implemented locally, awaiting review** (166 test expectations pass; checked in Chrome: dark/light, a real recommendation, empty and over-long prompts, cooldown, OpenAI-failure state; production Docker build being verified). Not committed or deployed |
| 2 | Phase 2: infrastructure (project move?, runtime account, Actions auto-deploy, Dependabot, Dockerfile, docs) | Not started |

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
- Keep the current brand look (red `#C1272D`, Spotify green, background `#191414`, Gotham), **dark by default**, with a light mode and a toggle (`bslib::input_dark_mode(mode = "dark")`); CSS custom properties so colours live in one place; check contrast in both modes (brand red is only 3.1:1 on `#191414`; FillariStatus uses `#F26B70` for dark-mode links).
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

### 5.1 Move to the BiblioStatus project? (decide before doing anything)
**For:** one project, one billing account and budget alert, one place for IAM; the FillariStatus and BiblioStatus setup (`github-deploy`, runtime accounts) already exists there.
**Against / costs:** secrets must be recreated (never printed); a new Cloud Run service; the custom domain mapping `tuneteller.youcanbeapirate.com` must be deleted and recreated, and the certificate takes ~15–30 min to be issued again (a short outage, or switch DNS only after the new service has a ready certificate); the old project and service must be cleaned up afterwards.
**Observed in `tuneteller-app`:** besides `tuneteller-app` (ready) the project also lists `bibliostatus-app` and `gallery-of-the-day-app` services that show as *not ready* (`gcloud run services list`, 2026-10-18); find out what they are before deleting anything.
**Recommendation:** decide after listing what the old project contains; if moving, build the new service first, verify it on its `run.app` URL, then switch the domain.

### 5.2 Identity and deploy
- Dedicated runtime service account `tuneteller-runtime` with `secretAccessor` on only the three secrets (`openai-api-key`, `spotify-client-id`, `spotify-client-secret`), replacing the default compute account.
- **Keyless deploys:** a new Workload Identity pool and provider for the TuneTeller repo (pool distinct from the existing `github` pool, as requested), mapped to a deploy service account; GitHub Actions workflow on pushes touching `app/**` or the build files: build, deploy, smoke test; a test job gating the deploy; actions pinned to SHAs; serialised runs. A new IAM binding can take minutes to work (FillariStatus first run failed with `getAccessToken denied`).
- `dependabot.yml` for Actions and the Docker base image; repository hygiene (secret scanning, push protection, protected `main`).

### 5.3 Image and docs
- Dockerfile: pinned base image, non-root runtime user, renv cache disabled at build, system libraries from P3M sysreqs; allowlist `.dockerignore` so `.env` and other secrets can never end up in the image.
- Check Cloud Run `--concurrency` against the number of assets per page load (§6 gotcha), keep `--session-affinity`, a sensible `--max-instances`.
- Update `DEPLOY.md`, `README.md`, `CLAUDE.md` (and this plan).

## 6. Gotchas carried over from FillariStatus (relevant here)
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
