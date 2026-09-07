# Sandbox `cluster-t5lkh` — RHOAI 3.5 "Fraud detection" tutorial, executed end-to-end

Reproduces, headlessly and declaratively, the official tutorial:
[OpenShift AI tutorial - Fraud detection example (RHOAI 3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/openshift_ai_tutorial_-_fraud_detection_example/index)

Manifests: `manifests/fraud-detection-tutorial/`. Script:
`scripts/install-fraud-detection-tutorial.sh` (`make install-fraud-detection-tutorial`).

Everything the tutorial says to click through the dashboard/JupyterLab UI for
was instead applied via `oc apply` / `oc exec` (same end resources, no
browser needed on this side). **Results are real**: a model was actually
trained, uploaded, deployed, and queried over its REST API — see
[Results](#results) below.

## What was created (maps 1:1 to the tutorial's chapters)

| Tutorial step | Resource(s) created | Namespace |
|---|---|---|
| Ch.2.2 Create your project | `Namespace/fraud-detection` (Data Science Project) | — |
| Ch.2.3 Run automated script for local object storage | `Deployment/s4` ("S4" = disposable local S3), `Secret/my-storage`, `Secret/pipeline-artifacts` (the two **Connections**), `Route/s4`, `Route/s4-api` — via the tutorial's own [`setup-s3-no-sa.yaml`](https://github.com/rh-aiservices-bu/fraud-detection/blob/main/setup/setup-s3-no-sa.yaml) | `fraud-detection` |
| Ch.2.4 Enable AI pipelines | `DataSciencePipelinesApplication/dspa` (what "Configure pipeline server" creates), using the `pipeline-artifacts` connection | `fraud-detection` |
| Ch.3.1 Create a workbench | `PersistentVolumeClaim/fraud-detection` (20Gi), `Notebook/fraud-detection` — image `tensorflow:2025.2` (Jupyter \| Tensorflow \| CUDA \| Python 3.12), `default-profile` hardware profile, `my-storage` connection attached via `envFrom` | `fraud-detection` |
| Ch.3.2 Import tutorial files | `git clone --recurse-submodules https://github.com/rh-aiservices-bu/fraud-detection.git`, checked out to branch `v3.5`, run inside the workbench pod (`oc exec`) | `fraud-detection` pod `fraud-detection-0` |
| Ch.3.4 Train the model | `jupyter nbconvert --execute 1_experiment_train.ipynb` (headless run of the exact notebook cells) | same pod |
| Ch.4.1 Prepare the model for deployment | `jupyter nbconvert --execute 2_save_model.ipynb` → uploads `models/fraud/1/model.onnx` to the `my-storage` S3 bucket | same pod |
| Ch.4.2 Deploy the model | `ServiceAccount/fraud-detection-sa`, `ServingRuntime/kserve-ovms` (OpenVINO Model Server, copied from the `redhat-ods-applications/kserve-ovms` Template — same one the dashboard wizard uses), `InferenceService/fraud` (KServe `RawDeployment` mode, `onnx-1`, `storageUri: s3://my-storage/models/fraud`) | `fraud-detection` |
| Ch.4.3 Test the model API | `jupyter nbconvert --execute 3_rest_requests.ipynb` (the tutorial's own REST-call notebook, endpoint patched to `http://fraud-predictor.fraud-detection.svc.cluster.local:8888`, exactly matching the tutorial's note about needing port `8888`) | same pod |

Chapters 5 (pipelines via the Elyra GUI editor) and 6/7 (distributed
training with Ray/Kueue/Kubeflow Trainer) and 8 (Feast feature store) are
**optional** sections of the tutorial and were not run — the pipeline
*server* is configured and ready (Ch.2.4) if you want to do Ch.5 yourself
from JupyterLab.

## Results

Training (`1_experiment_train.ipynb`, 2 epochs, CPU only, ~2m17s):

```
Eval Metrics:
 Accuracy: 97.7%, Precision: 0.9948, Recall: 0.7392
```

Model uploaded to object storage: `s3://my-storage/models/fraud/1/model.onnx` (13,241 bytes).

`InferenceService/fraud` status: `Ready=True`, `activeModelState=Loaded`, `Stopped=False` — the same state the dashboard's Deployments page shows as **Started**.

Live REST API test (`3_rest_requests.ipynb`, KServe v2 inference protocol, `POST /v2/models/fraud/infer`) against three sample transactions:

| Scenario | Score | Verdict |
|---|---|---|
| Small distance, price near median, chip used ("Sally") | 0.00104 | not fraud |
| Far away, high price ratio, chip+pin+online | 0.00000 | not fraud |
| Very far away, no chip/pin, online purchase | 0.99589 | **fraud** |

## Where to click — visually verify the same thing in the dashboard

Everything below was already created for you by the script above; this
section just tells you **where to look** to see it, following the exact
same navigation the official tutorial describes.

1. **Dashboard home** — open
   `https://rhods-dashboard-redhat-ods-applications.apps.cluster-t5lkh.dyn.redhatworkshops.io`
   (or: OpenShift console → application-launcher icon (⚏, top header) →
   **Red Hat OpenShift AI**). Log in with your OpenShift credentials.

2. **Data Science Projects → fraud-detection** — left nav → **Data Science Projects** → click **Fraud detection** (well, `fraud-detection`). You land on the project detail page with tabs:
   `Workbenches | Pipelines | Deployments | Cluster storage | Connections | Permissions`.

3. **Connections tab** — click it. You'll see two connections: **My Storage** and **Pipeline Artifacts** (created by the S4 setup job, Ch.2.3).

4. **Pipelines tab** — click it, then the (⋮) action menu next to "Import pipeline" → **Manage pipeline server configuration** — confirms the pipeline server (Ch.2.4) is configured and pointed at the `pipeline-artifacts` connection. (Chapter 5's GUI pipeline-editor exercise is still available to run yourself from the workbench if you want to explore it — it's optional.)

5. **Workbenches tab** — click it. You'll see **fraud-detection**, status **Running**. Click its name to open JupyterLab (OAuth login if prompted). Inside:
   - File browser (left icon) shows the `fraud-detection/` folder (the cloned git repo).
   - `1_experiment_train.ipynb`, `2_save_model.ipynb`, `3_rest_requests.ipynb` are all already **executed** — open any of them and you'll see the outputs (training log, accuracy/precision/recall, confusion matrix plot, S3 upload confirmation, REST predictions) exactly as if you had clicked ▶ **Run** on every cell yourself.
   - Direct link (once logged in via OAuth in your browser):
     `https://rh-ai.apps.cluster-t5lkh.dyn.redhatworkshops.io/notebook/fraud-detection/fraud-detection/`

6. **Deployments tab** — click it. You'll see model **fraud**, framework **onnx-1**, serving runtime **OpenVINO Model Server**, status **Started**. Click the row to expand it and see the **Inference endpoint** — internally
   `http://fraud-predictor.fraud-detection.svc.cluster.local` (append `:8888` when calling it from inside a workbench, per the tutorial's own note in Ch.4.3).

7. To re-run the REST test yourself interactively: in JupyterLab, open `3_rest_requests.ipynb` and click ▶ on each cell — it's pre-configured with the right endpoint and will reproduce the "fraud" / "not fraud" verdicts shown above.

## Files

- `manifests/fraud-detection-tutorial/00-demo-setup-rbac.yaml` — `demo-setup` ServiceAccount + edit RoleBinding (mirrors the tutorial's `setup-s3-job.yaml` wrapper).
- `manifests/fraud-detection-tutorial/01-namespace.yaml` — the Data Science Project.
- `manifests/fraud-detection-tutorial/02-setup-s3-no-sa.yaml` — verbatim copy of the [tutorial's S4 storage manifest](https://github.com/rh-aiservices-bu/fraud-detection/blob/main/setup/setup-s3-no-sa.yaml).
- `manifests/fraud-detection-tutorial/03-dspa.yaml` — pipeline server (`DataSciencePipelinesApplication`).
- `manifests/fraud-detection-tutorial/04-workbench-pvc.yaml`, `05-workbench-notebook.yaml` — the workbench.
- `manifests/fraud-detection-tutorial/06-serving-sa.yaml`, `07-servingruntime-ovms.yaml`, `08-inferenceservice.yaml` — the model deployment.
- `scripts/install-fraud-detection-tutorial.sh` — runs all of the above in order, waits for readiness at each step, and headlessly executes the three notebooks.

## Notes / gotchas hit along the way

- The `my-storage`/`pipeline-artifacts` Secrets created by the tutorial's own S4 job don't carry the `serving.kserve.io/s3-*` annotations KServe's S3 storage-initializer needs. The dashboard's "Deploy model" wizard adds these silently when you pick "Existing connection"; doing it via CLI required `oc annotate secret my-storage serving.kserve.io/s3-endpoint=... s3-usehttps=0 s3-verifyssl=0 s3-region=us-east-1` first.
- `fraud-predictor` is a **headless** Service (`ClusterIP: None`). Its declared port is `80→8888`, but because it's headless, clients resolve straight to the pod IP and must dial the container's actual port (`8888`), not `80` — exactly why the tutorial's Ch.4.3 note says "you might need to edit the endpoint to specify `8888` for the port".
- `KServe` on this cluster runs in `RawDeployment` mode (not Serverless/Knative) — the `InferenceService.status.components.predictor.url` shows a placeholder `*.example.com` host; the real, working URL is the ClusterIP service URL (`status.url`).
