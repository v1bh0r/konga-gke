#!/usr/bin/env bash
# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Apply the PgAdmin configmap, secret, and deployment manifests to the cluster.

# "---------------------------------------------------------"
# "-                                                       -"
# "-  Apply the PgAdmin configmap, secret, and deployment  -"
# "-  manifests to the cluster.                            -"
# "-                                                       -"
# "---------------------------------------------------------"

# Bash safeties: exit on error, no unset variables, pipelines can't hide errors
set -euo pipefail

# Directory of this script.
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# shellcheck source=scripts/common.sh
source "$ROOT"/scripts/common.sh

# Ensure the bastion SSH tunnel/proxy is up/running
# shellcheck source=scripts/proxy.sh
source "$ROOT"/scripts/proxy.sh

# Set the HTTPS_PROXY env var to allow kubectl to bounce through
# the bastion host over the locally forwarded port 8888.
export HTTPS_PROXY=localhost:8888

# Create the configmap that includes the connection string for the DB.
echo 'Creating the Configmap'
POSTGRES_CONNECTION="$(cd terraform && terraform output postgres_connection)"
POSTGRES_PRIVATE_IP="$(cd terraform && terraform output postgres_private_ip)"
kubectl create configmap pgconnection \
  --from-literal=connectionname="${POSTGRES_CONNECTION}" \
  --from-literal=postgres_private_ip="${POSTGRES_PRIVATE_IP}" \
  --dry-run -o yaml | kubectl apply -f -

# Create the secret that includes the user/pass for pgadmin
echo 'Creating the Console secret'
POSTGRES_USER="$(cd terraform && terraform output postgres_user)"
POSTGRES_PASS="$(cd terraform && terraform output postgres_pass)"
kubectl create secret generic pgadmin-console \
  --from-literal=user="${POSTGRES_USER}" \
  --from-literal=password="${POSTGRES_PASS}" \
  --dry-run -o yaml | kubectl apply -f -

# Create the service account
kubectl create serviceaccount postgres -n default \
  --dry-run -o yaml | kubectl apply -f -

# Annotate it
GCP_SA="$(cd terraform && terraform output gcp_serviceaccount)"
kubectl annotate serviceaccount -n default postgres --overwrite=true \
  iam.gke.io/gcp-service-account="${GCP_SA}"

echo 'Deploying Kong'
kubectl apply -f "${ROOT}/manifests/kong-deployment.yaml"

# Make sure kong is running successfully.
echo 'Waiting for rollout to complete and pod available.'
kubectl rollout status --timeout=5m deployment/ingress-kong

echo 'Deploying Konga'
kubectl apply -f "${ROOT}/manifests/konga-deployment.yaml"

# Make sure kong is running successfully.
echo 'Waiting for rollout to complete and pod available.'
kubectl rollout status --timeout=5m deployment/konga-deployment
