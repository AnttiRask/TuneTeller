# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TuneTeller is an R/Shiny web app that recommends music artists via OpenAI (GPT-4o-mini) and Spotify API. Users describe music they want in natural language, OpenAI suggests an artist, and Spotify provides artist details (image, followers, profile link).

## Development Commands

```bash
# Install R dependencies
R -e "renv::restore()"

# Run locally (requires env vars set)
R -e 'shiny::runApp("app/")'

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

The app follows a standard Shiny `ui.R`/`server.R` split:

- **`app/run.R`** - Entry point; starts the Shiny server on `$PORT` (default 8080)
- **`app/ui.R`** - UI definition using `bslib::page_fluid` with Bootstrap 5 dark theme. Contains `create_app_footer()`, a shared footer component used across multiple youcanbeapirate.com apps (BiblioStatus, Gallery of the Day, TrackTeller, TuneTeller)
- **`app/server.R`** - Server logic with two main reactive flows:
  1. `observeEvent(input$go)` sends the user's prompt to OpenAI's `/v1/responses` endpoint, parses the response to extract artist name and description, and caches the result in `recommendation_cache` reactiveVal
  2. `artist_details()` reactive takes the cached recommendation, searches Spotify via `search_spotify_artist()` (`app/www/spotify.R`, `httr2`), and returns artist metadata (image, followers, Spotify URL)
- **`app/www/prompt_versions.R`** - OpenAI prompt templates using `stringr::str_glue` interpolation (currently uses `prompt_ver2`)
- **`app/www/styles.css`** - Custom dark theme CSS; brand color is `#C1272D`, Spotify green is `#1DB954`, background is `#191414`

## Key Conventions

- R code uses Tidyverse syntax and packages (dplyr, purrr, stringr)
- HTTP requests use `httr2` (not httr)
- Package management via `renv` - update `renv.lock` when adding/removing packages
- Dockerfile must copy `.Rprofile`, `renv/activate.R`, and `renv/settings.json` before `renv::restore()`
- The footer in `ui.R` is standardized across apps - keep format consistent when modifying

## Deployment

- Deployed on Google Cloud Run in `europe-north1`, project `tuneteller-app`
- Production secrets stored in GCP Secret Manager (not env vars)
- `docker compose restart` does NOT re-read `.env` - use `docker compose up -d --force-recreate`
