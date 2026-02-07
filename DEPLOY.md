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

3. Open http://localhost:8080

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
       --timeout 300
   ```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `OPENAI_API_KEY` | OpenAI API key for GPT-4o-mini recommendations |
| `SPOTIFY_CLIENT_ID` | Spotify Developer app client ID |
| `SPOTIFY_CLIENT_SECRET` | Spotify Developer app client secret |

## Cost

Google Cloud Run has a generous free tier that covers personal use:
- 2 million requests/month
- 360,000 GB-seconds of memory
- 180,000 vCPU-seconds of compute
