#!/usr/bin/env bash
# install-fraud-detection-tutorial.sh - Reproduce, end-to-end and headlessly,
# the official RHOAI 3.5 "Fraud detection example" tutorial:
#   https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/openshift_ai_tutorial_-_fraud_detection_example/index
#
# What this does, matching each tutorial chapter:
#   Ch.2 Setting up a project and storage
#     - Data Science Project "fraud-detection"
#     - Local S3-compatible storage (the tutorial's own "S4" job from
#       github.com/rh-aiservices-bu/fraud-detection, run declaratively
#       instead of pasted into "Import YAML" in the OpenShift console)
#     - Pipeline server (DataSciencePipelinesApplication CR == what
#       "Configure pipeline server" creates)
#   Ch.3 Creating a workbench and using notebooks
#     - Notebook CR: Jupyter | Tensorflow | CUDA | Python 3.12 (2025.2),
#       "My Storage" connection attached
#     - git clone (branch v3.5) + headless run of 1_experiment_train.ipynb
#       and 2_save_model.ipynb via `jupyter nbconvert --execute`
#   Ch.4 Deploying and testing a model
#     - ServingRuntime (OpenVINO Model Server) + InferenceService "fraud"
#     - Headless run of 3_rest_requests.ipynb against the internal
#       fraud-predictor service (port 8888, matching the tutorial's own
#       "you may need to specify port 8888" note)
#
# Idempotent-ish: safe to re-run (oc apply); the notebook-execution steps
# will simply retrain/re-upload/retest if you re-run them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_login

MANIFEST_DIR="$MANIFESTS/fraud-detection-tutorial"
NS=fraud-detection
WORKBENCH=fraud-detection
REPO_URL="https://github.com/rh-aiservices-bu/fraud-detection.git"

info "Ch.2 -- Creating the 'fraud-detection' Data Science Project"
oc apply -f "$MANIFEST_DIR/01-namespace.yaml"

info "Ch.2.3 -- Local S3 storage (S4): RBAC + the tutorial's own setup-s3-no-sa.yaml"
oc apply -n "$NS" -f "$MANIFEST_DIR/00-demo-setup-rbac.yaml"
oc apply -n "$NS" -f "$MANIFEST_DIR/02-setup-s3-no-sa.yaml"

info "Waiting for the S4 setup Jobs (credentials, buckets, connections) to complete..."
oc wait --for=condition=complete --timeout=180s \
  job/create-s4-credentials-secret job/create-s4-buckets job/create-ds-connections -n "$NS"
ok "Connections 'my-storage' and 'pipeline-artifacts' created."

info "Ch.2.4 -- Configuring the pipeline server (DataSciencePipelinesApplication)"
oc apply -f "$MANIFEST_DIR/03-dspa.yaml"
info "Waiting for the DSPA to become Ready (timeout ~2m)..."
for i in $(seq 1 24); do
  READY=$(oc get dspa dspa -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [[ "$READY" == "True" ]] && { ok "Pipeline server Ready"; break; }
  [[ "$i" == "24" ]] && warn "Pipeline server not Ready after 2m, check 'oc get dspa dspa -n $NS'"
  sleep 5
done

info "Ch.3.1 -- Creating workbench '$WORKBENCH' (Jupyter | Tensorflow | CUDA | Python 3.12, 2025.2)"
oc apply -f "$MANIFEST_DIR/04-workbench-pvc.yaml"
oc apply -f "$MANIFEST_DIR/05-workbench-notebook.yaml"

info "Waiting for workbench pod to become Ready (first pull of the CUDA/Tensorflow image is slow, ~5min)..."
for i in $(seq 1 60); do
  READY=$(oc get pod "$WORKBENCH-0" -n "$NS" -o jsonpath='{.status.containerStatuses[?(@.name=="'"$WORKBENCH"'")].ready}' 2>/dev/null || true)
  [[ "$READY" == "true" ]] && { ok "Workbench pod Ready"; break; }
  [[ "$i" == "60" ]] && { warn "Workbench pod not Ready after 10m, check 'oc get pod $WORKBENCH-0 -n $NS'"; }
  sleep 10
done

info "Ch.3.2 -- Cloning the tutorial repo (branch v3.5) into the workbench"
oc exec -n "$NS" "$WORKBENCH-0" -c "$WORKBENCH" -- bash -lc \
  "cd /opt/app-root/src && [ -d fraud-detection ] || git clone --recurse-submodules '$REPO_URL' && cd fraud-detection && git checkout v3.5"

info "Ch.3.4 -- Running 1_experiment_train.ipynb headlessly (trains + saves models/fraud/1/model.onnx; ~3min)"
oc exec -n "$NS" "$WORKBENCH-0" -c "$WORKBENCH" -- bash -lc \
  "cd /opt/app-root/src/fraud-detection && jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.timeout=1800 1_experiment_train.ipynb"
ok "Model trained."

info "Ch.4.1 -- Running 2_save_model.ipynb headlessly (uploads model.onnx to the 'My Storage' S3 bucket)"
oc exec -n "$NS" "$WORKBENCH-0" -c "$WORKBENCH" -- bash -lc \
  "cd /opt/app-root/src/fraud-detection && jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.timeout=600 2_save_model.ipynb"
ok "Model uploaded to s3://my-storage/models/fraud/1/model.onnx"

info "Ch.4.2 -- Deploying the model (OpenVINO Model Server / KServe RawDeployment)"
oc annotate secret my-storage -n "$NS" --overwrite \
  serving.kserve.io/s3-endpoint="s4.$NS.svc.cluster.local:7480" \
  serving.kserve.io/s3-usehttps="0" \
  serving.kserve.io/s3-verifyssl="0" \
  serving.kserve.io/s3-region="us-east-1"
oc apply -f "$MANIFEST_DIR/06-serving-sa.yaml"
oc apply -f "$MANIFEST_DIR/07-servingruntime-ovms.yaml"
oc apply -f "$MANIFEST_DIR/08-inferenceservice.yaml"

info "Waiting for the InferenceService to become Ready (pulls model from S3; ~1min)..."
for i in $(seq 1 24); do
  READY=$(oc get inferenceservice fraud -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [[ "$READY" == "True" ]] && { ok "InferenceService 'fraud' Ready"; break; }
  [[ "$i" == "24" ]] && warn "InferenceService not Ready after 2m, check 'oc get inferenceservice fraud -n $NS'"
  sleep 5
done

info "Ch.4.3 -- Testing the model API (running the tutorial's own 3_rest_requests.ipynb)"
oc exec -n "$NS" "$WORKBENCH-0" -c "$WORKBENCH" -- python3 -c "
import json
path='/opt/app-root/src/fraud-detection/3_rest_requests.ipynb'
nb=json.load(open(path))
for c in nb['cells']:
    if c['cell_type']=='code' and 'infer_endpoint' in ''.join(c['source']):
        c['source'] = [
            'deployed_model_name = \"fraud\"\n',
            'infer_endpoint = \"http://fraud-predictor.$NS.svc.cluster.local:8888\"\n',
            'infer_url = f\"{infer_endpoint}/v2/models/{deployed_model_name}/infer\"'
        ]
        break
json.dump(nb, open(path,'w'))
"
oc exec -n "$NS" "$WORKBENCH-0" -c "$WORKBENCH" -- bash -lc \
  "cd /opt/app-root/src/fraud-detection && jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.timeout=120 3_rest_requests.ipynb"
ok "Inference API tested successfully."

GW_ROUTE_HOST=$(oc get route -n openshift-ingress -o jsonpath='{range .items[*]}{.spec.to.name}{" "}{.spec.host}{"\n"}{end}' \
  | awk '/data-science-gateway/ {print $2}' | head -1)
echo
ok "Fraud detection tutorial fully reproduced in the '$NS' project."
ok "Workbench:  https://${GW_ROUTE_HOST:-<gateway route not found>}/notebook/$NS/$WORKBENCH/"
ok "Dashboard project page: https://$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null)/projects/$NS"
