#!/bin/bash
# Deploy TuneTeller to Google Cloud Run

set -e

# Configuration
PROJECT_ID="${GCP_PROJECT:-tuneteller-app}"
REGION="${GCP_REGION:-europe-north1}"
SERVICE_NAME="tuneteller-app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== TuneTeller Deployment ===${NC}"

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI is not installed${NC}"
    echo "Install it from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if logged in
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    echo -e "${YELLOW}Please login to Google Cloud:${NC}"
    gcloud auth login
fi

# Set project (create if it doesn't exist)
echo -e "${YELLOW}Setting project to: ${PROJECT_ID}${NC}"
if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
    echo -e "${YELLOW}Project doesn't exist. Creating...${NC}"
    gcloud projects create "$PROJECT_ID" --name="TuneTeller"
fi
gcloud config set project "$PROJECT_ID"

# Enable required APIs
echo -e "${YELLOW}Enabling required APIs...${NC}"
gcloud services enable cloudbuild.googleapis.com run.googleapis.com artifactregistry.googleapis.com

# Enable Secret Manager API
echo -e "${YELLOW}Enabling Secret Manager API...${NC}"
gcloud services enable secretmanager.googleapis.com

# Deploy to Cloud Run using Cloud Secrets Manager
echo -e "${GREEN}Deploying to Cloud Run...${NC}"
gcloud run deploy "$SERVICE_NAME" \
    --source . \
    --platform managed \
    --region "$REGION" \
    --allow-unauthenticated \
    --set-secrets "OPENAI_API_KEY=openai-api-key:latest" \
    --set-secrets "SPOTIFY_CLIENT_ID=spotify-client-id:latest" \
    --set-secrets "SPOTIFY_CLIENT_SECRET=spotify-client-secret:latest" \
    --memory 1Gi \
    --timeout 300

# Get the service URL
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format="value(status.url)")

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo -e "Your app is live at: ${GREEN}${SERVICE_URL}${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Verify the app works at the URL above"
echo -e "2. If you have a custom domain, map it with:"
echo -e "   gcloud beta run domain-mappings create --service $SERVICE_NAME --domain tuneteller.youcanbeapirate.com --region $REGION"
echo -e "3. For production, consider using Cloud Secrets Manager (see DEPLOY.md)"
