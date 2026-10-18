# Deploying TuneTeller to Google Cloud Run

## Prerequisites

1. [Google Cloud SDK (gcloud CLI)](https://cloud.google.com/sdk/docs/install) installed
2. A Google Cloud account with billing enabled
3. API credentials:
   - **OpenAI API Key** from [OpenAI Platform](https://platform.openai.com/api-keys)
   - **Spotify Client ID & Secret** from [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)

## Local Development with Docker

1. Copy the environment template and fill in your credentials:

   ```bash
   cp .env.example .env
   # Edit .env with your actual API keys
   ```

2. Build and run:

   ```bash
   docker compose up --build
   ```

3. Open http://localhost:8081

## Deploy to Google Cloud Run

### Option 1: Using deploy.sh (recommended)

1. Set up your `.env` file (see above), then run:

   ```bash
   ./deploy.sh
   ```

   The script will:
   - Create the GCP project `tuneteller-app` if it doesn't exist
   - Enable required APIs (Cloud Build, Cloud Run, Artifact Registry)
   - Read credentials from `.env` or prompt you
   - Deploy to Cloud Run in `europe-north1`

### Option 2: Manual deployment

1. Set the project and enable APIs:

   ```bash
   gcloud config set project tuneteller-app
   gcloud services enable cloudbuild.googleapis.com run.googleapis.com artifactregistry.googleapis.com
   ```

2. Deploy:

   ```bash
   gcloud run deploy tuneteller-app \
       --source . \
       --platform managed \
       --region europe-north1 \
       --allow-unauthenticated \
       --set-env-vars "OPENAI_API_KEY=your-key" \
       --set-env-vars "SPOTIFY_CLIENT_ID=your-id" \
       --set-env-vars "SPOTIFY_CLIENT_SECRET=your-secret" \
       --memory 1Gi \
       --timeout 3600 \
       --session-affinity \
       --max-instances 3
   ```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `OPENAI_API_KEY` | OpenAI API key for GPT-4o-mini recommendations |
| `SPOTIFY_CLIENT_ID` | Spotify Developer app client ID |
| `SPOTIFY_CLIENT_SECRET` | Spotify Developer app client secret |

## Using Secrets (Recommended for Production)

For better security, store credentials as secrets:

```bash
# Enable the Secret Manager API
gcloud services enable secretmanager.googleapis.com

# Create secrets
echo -n "your_openai_key" | gcloud secrets create openai-api-key --data-file=-
echo -n "your_client_id" | gcloud secrets create spotify-client-id --data-file=-
echo -n "your_client_secret" | gcloud secrets create spotify-client-secret --data-file=-

# Grant Cloud Run access to secrets
PROJECT_NUMBER=$(gcloud projects describe tuneteller-app --format="value(projectNumber)")

for SECRET in openai-api-key spotify-client-id spotify-client-secret; do
  gcloud secrets add-iam-policy-binding $SECRET \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
done

# Deploy with secrets
gcloud run deploy tuneteller-app \
  --source . \
  --platform managed \
  --region europe-north1 \
  --allow-unauthenticated \
  --set-secrets "OPENAI_API_KEY=openai-api-key:latest" \
  --set-secrets "SPOTIFY_CLIENT_ID=spotify-client-id:latest" \
  --set-secrets "SPOTIFY_CLIENT_SECRET=spotify-client-secret:latest" \
  --memory 1Gi \
  --timeout 3600 \
  --session-affinity \
  --max-instances 3
```

**Keep `--max-instances 3`.** TuneTeller's cooldown is per session, so a script that opens many sessions could otherwise make many paid OpenAI calls; three instances at 80 requests each is plenty for this app and caps the damage. Raise it only if traffic really needs it.

**Keep `--timeout 3600` and `--session-affinity`.** Cloud Run's timeout also caps how long Shiny's websocket can stay open: at the default 300 s the connection is closed after 5 minutes and the page greys out ("Disconnected from server") even for an active user. 3600 s is the most Cloud Run allows, so a page left open for over an hour (or a network drop) still greys out until it is reloaded.

**`session$allowReconnect(TRUE)` (in `server.R`) does not help.** The Shiny client only reconnects if the host (Shiny Server, Posit Connect) allows it too, and Cloud Run with plain Shiny does not: closing the websocket by hand (`Shiny.shinyapp.$socket.close()`) leaves the page greyed out and disconnected. It is kept only for parity with the other apps. `session$allowReconnect("force")` does make the client reconnect (FillariStatus and BiblioStatus use it), but **not for TuneTeller as it stands**: a reconnect starts a new session and the browser re-sends its inputs, including the "Get Recommendation" click count, so `recommendation_result` would run again and make a paid OpenAI call nobody asked for. To use `"force"` here, first make that observer ignore a click count that was already handled. Session affinity keeps the requests of one browser on one instance.

## Cost

Google Cloud Run has a generous free tier that covers personal use:
- 2 million requests/month
- 360,000 GB-seconds of memory
- 180,000 vCPU-seconds of compute

For a personal project with occasional use, this should be **completely free**.

## Updating the App

To deploy updates:

```bash
gcloud run deploy tuneteller-app --source .
```

## Monitoring

View logs:

```bash
gcloud run logs read tuneteller-app --region europe-north1
```

View in console:

- [Cloud Run Console](https://console.cloud.google.com/run)


## Automatic deploys (GitHub Actions)

A push to `main` that changes `app/**`, `Dockerfile`, `.dockerignore`, `renv.lock`, `.Rprofile` or `renv/activate.R|settings.json` runs `.github/workflows/deploy_shiny_app.yml`: the tests (`tests.yml`) must pass, then the app is built and deployed to Cloud Run, and a smoke test checks that the service carries the commit's `git-sha` label and answers HTTP 200. Docs-only or tests-only pushes don't deploy. To deploy by hand: Actions tab > "Deploy to Cloud Run" > Run workflow (from `main`). `./deploy.sh` still works; keep its flags in sync with the workflow.

There are no stored keys. The workflow logs in through **Workload Identity Federation**: pool `tuneteller`, provider `github-oidc` in project `tuneteller-app`, which only accepts `AnttiRask/TuneTeller` on `refs/heads/main`. It then acts as the service account `tuneteller-deploy`, which can deploy only the `tuneteller-app` service (see `tuneteller-refactor-plan.md` §5.2 for its exact permissions). The service itself runs as `tuneteller-runtime`, which can read only its three secrets.

The workflow doesn't pass `--allow-unauthenticated` (the service is already public and the deploy account may not change IAM). If you ever need to make the service public again, do it yourself with your own account.
