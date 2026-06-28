#!/bin/bash

set -euo pipefail

#############################################
# Colors
#############################################

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

#############################################
# Helper Functions
#############################################

wait_for_service_account() {

    local EMAIL="$1"

    echo "Waiting for $EMAIL..."

    until gcloud iam service-accounts describe "$EMAIL" >/dev/null 2>&1
    do
        sleep 2
    done

    echo "✓ $EMAIL is ready."

}

#############################################
# Banner
#############################################

echo -e "${BLUE}"
echo "======================================"
echo " GCP Billing Kill Switch Installer"
echo "======================================"
echo -e "${NC}"

#############################################
# Input
#############################################

read -p "Project ID: " PROJECT_ID
read -p "Billing Account ID: " BILLING_ACCOUNT
read -p "Budget Amount (USD): " BUDGET

REGION="us-central1"

#############################################
# Configure project
#############################################

echo -e "${GREEN}Setting project...${NC}"

gcloud config set project "$PROJECT_ID"

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" \
--format="value(projectNumber)")

echo "Project Number: $PROJECT_NUMBER"

#############################################
# Enable APIs
#############################################

echo -e "${GREEN}Enabling APIs...${NC}"

gcloud services enable \
cloudbilling.googleapis.com \
billingbudgets.googleapis.com \
pubsub.googleapis.com \
cloudfunctions.googleapis.com \
run.googleapis.com \
artifactregistry.googleapis.com \
cloudbuild.googleapis.com \
eventarc.googleapis.com \
iam.googleapis.com

#############################################
# Variables
#############################################

FUNCTION_SA="billing-kill-switch-sa"
INVOKER_SA="kill-switch-invoker-sa"

TOPIC="budget-alert-topic"

FUNCTION="billing-kill-switch-func"

#############################################
# Create Service Accounts
#############################################

echo -e "${GREEN}Creating service accounts...${NC}"

if ! gcloud iam service-accounts describe \
$FUNCTION_SA@$PROJECT_ID.iam.gserviceaccount.com \
>/dev/null 2>&1
then

gcloud iam service-accounts create $FUNCTION_SA \
--display-name="Billing Kill Switch"

fi

if ! gcloud iam service-accounts describe \
$INVOKER_SA@$PROJECT_ID.iam.gserviceaccount.com \
>/dev/null 2>&1
then

gcloud iam service-accounts create $INVOKER_SA \
--display-name="Kill Switch Invoker"

fi

#############################################
# Wait for IAM propagation
#############################################

wait_for_service_account \
"$FUNCTION_SA@$PROJECT_ID.iam.gserviceaccount.com"

wait_for_service_account \
"$INVOKER_SA@$PROJECT_ID.iam.gserviceaccount.com"

#############################################
# IAM Roles
#############################################

echo -e "${GREEN}Granting IAM roles...${NC}"

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member="serviceAccount:$FUNCTION_SA@$PROJECT_ID.iam.gserviceaccount.com" \
--role="roles/billing.projectManager"

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member="serviceAccount:$INVOKER_SA@$PROJECT_ID.iam.gserviceaccount.com" \
--role="roles/run.invoker"

#############################################
# Billing Administrator
#############################################

echo -e "${GREEN}Grant Billing Administrator...${NC}"

gcloud beta billing accounts add-iam-policy-binding \
$BILLING_ACCOUNT \
--member="serviceAccount:$FUNCTION_SA@$PROJECT_ID.iam.gserviceaccount.com" \
--role="roles/billing.admin"

#############################################
# PubSub Topic
#############################################

echo -e "${GREEN}Creating Pub/Sub Topic...${NC}"

if ! gcloud pubsub topics describe "$TOPIC" >/dev/null 2>&1
then
    gcloud pubsub topics create "$TOPIC"
else
    echo "Pub/Sub topic already exists."
fi

#############################################
# Grant Cloud Build Builder Role
#############################################

echo -e "${GREEN}Granting Cloud Build Builder role...${NC}"

BUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
--member="serviceAccount:$BUILD_SA" \
--role="roles/cloudbuild.builds.builder"

#############################################
# Deploy Cloud Function
#############################################

echo -e "${GREEN}Deploying Cloud Function...${NC}"

gcloud functions deploy $FUNCTION \
--gen2 \
--runtime=python312 \
--region=$REGION \
--source=. \
--entry-point=stop_billing \
--trigger-http \
--service-account=$FUNCTION_SA@$PROJECT_ID.iam.gserviceaccount.com \
--set-env-vars=PROJECT_ID=$PROJECT_ID \
--max-instances=1 \
--no-allow-unauthenticated

#############################################
# Finished
#############################################

echo

echo -e "${GREEN}"
echo "======================================"
echo "Phase 2 Complete"
echo "======================================"

echo "Project : $PROJECT_ID"
echo "Billing : $BILLING_ACCOUNT"
echo "Budget  : $BUDGET"

echo -e "${NC}"