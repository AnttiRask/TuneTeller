# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TuneTeller is an R/Shiny web app that recommends music artists via OpenAI (GPT-5.4 nano) and Spotify API. Users describe music they want in natural language, OpenAI suggests an artist, and Spotify provides artist details (image, followers, profile link).

## Development Commands

```bash
# Install R dependencies
R -e "renv::restore()"

# Run locally (requires env vars set)
R -e 'shiny::runApp("app/")'

# Run the tests (mocked HTTP, no keys needed)
Rscript -e 'testthat::test_dir("tests/testthat")'

# Run with Docker (reads .env file)
docker compose up --build        # first time / after changes
docker compose up -d             # background
# App available at http://localhost:8081

# Deploy to Google Cloud Run
./deploy.sh
```

## Required Environment Variables

Copy `.env.example` to `.env` and fill in: `OPENAI_API_KEY`, `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`.

## Architecture

The app follows a standard Shiny `ui.R`/`server.R` split, with `global.R` loading libraries and sourcing `app/www/*.R`:

- **`app/run.R`** - Entry point; sets the working directory to `app/`, wraps the app's page handler with the security headers and starts the server on `$PORT` (default 8080)
- **`app/global.R`** - Libraries, then sources `variables.R`, `strings.R`, `prompt_versions.R`, `functions.R`, `api.R`
- **`app/ui.R`** - `bslib::page_fluid` with Bootstrap 5, dark by default and a light/dark switch (our own button, `mode_toggle_button()` + `www/mode-toggle.js`, because bslib's `input_dark_mode()` always shows the current mode and its icon can't be restyled). Contains `create_app_footer()`, a shared footer component used across multiple youcanbeapirate.com apps; its links come from `footer_apps` in `variables.R`
- **`app/server.R`** - Reactive logic only: `recommendation_result` (an `eventReactive` on `input$go`) cleans the prompt, enforces the 10 s cooldown, calls `get_recommendation()` then `find_artist()` and returns a state list (`ok` / `no_artist` / `error`) that `artist_card_ui()` renders. The spinner covers the whole request because the card output depends on it
- **`app/www/variables.R`** - Model name, limits (190 characters, 10 s cooldown, timeouts), brand colours, footer links
- **`app/www/strings.R`** - All user-facing text
- **`app/www/prompt_versions.R`** - Prompt versions; `prompt_ver3` (instructions + JSON schema) is current
- **`app/www/api.R`** - OpenAI (`/v1/responses`, JSON-schema output) and Spotify (client credentials, `httr2`). `get_recommendation()` and `find_artist()` never throw; they return `list(status, data)`
- **`app/www/functions.R`** - Pure helpers: `clean_prompt()`, `parse_recommendation()`, `theme_css()`, `artist_card_ui()`
- **`app/www/security.R`** - Security headers and `with_security_headers()`
- **`app/www/mode-toggle.js`** - Starts the page in dark mode and flips Bootstrap's `data-bs-theme`; the icon shows the mode a click switches to (sun while dark, moon while light)
- **`app/www/cooldown.js`** - Disables the button and shows the seconds left, driven by the server
- **`app/www/styles.css`** - Custom styles; colours come from CSS custom properties injected by `theme_css()`; brand color is `#C1272D`, Spotify green is `#1DB954`, dark background is `#191414`
- **`tests/testthat/`** - Tests with mocked HTTP (`httr2::local_mocked_responses()`); `helper-app.R` loads the app code

## Key Conventions

- R code uses Tidyverse syntax and packages (purrr, stringr); the existing files use `%>%`, so match that
- HTTP requests use `httr2` (not httr); Spotify is called directly, not through `spotifyr` (its 2.2.5 sends the token in the URL, which Spotify rejects with 401)
- Config goes in `variables.R`, user-facing text in `strings.R`; the OpenAI model is `openai_model` there (GPT-4o mini retires 2027-01-14)
- The model answers in JSON (schema in `prompt_versions.R`); nothing is parsed out of free text
- User text is cleaned (`clean_prompt()`) and fenced in `<request>` tags; everything from the model and Spotify is escaped by Shiny's tags, and only https links are used
- Never log prompts, keys or response bodies
- Package management via `renv` - update `renv.lock` when adding/removing packages
- Dockerfile must copy `.Rprofile`, `renv/activate.R`, and `renv/settings.json` before `renv::restore()`
- The footer in `ui.R` is standardized across apps - keep format consistent when modifying

## Deployment

- Deployed on Google Cloud Run in `europe-north1`, project `tuneteller-app`
- Production secrets stored in GCP Secret Manager (not env vars)
- Pushes to `main` that change `app/**` or the build files deploy automatically (`.github/workflows/deploy_shiny_app.yml`: tests, then build + deploy + smoke test; keyless login through Workload Identity Federation as `tuneteller-deploy`). Run the tests first and batch app changes into one push. Docs, tests and plan-only pushes don't deploy. See `DEPLOY.md`
- The service runs as `tuneteller-runtime` (only the 3 secrets), timeout 3600 s with session affinity (a shorter timeout makes the websocket drop after 5 minutes and the page grey out)
- `docker compose restart` does NOT re-read `.env` - use `docker compose up -d --force-recreate`
