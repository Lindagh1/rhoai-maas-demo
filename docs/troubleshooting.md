# Demo 1 troubleshooting

## Authentication / wrong cluster

**Symptom:** `oc` errors or unexpected project list.  
**Fix:** Re-login to the intended sandbox; confirm `oc whoami --show-server` contains the expected sandbox id. Abort if not disposable.

## RHCL CSV never Succeeded

**Checks:**
```bash
oc get sub rhcl-operator -n openshift-operators -o yaml
oc get csv -n openshift-operators | grep rhcl
oc get packagemanifest rhcl-operator -n openshift-marketplace
```
**Common causes:** OperatorHub / `redhat-operators` catalog unhealthy; channel typo (use `stable-1.4` for 1.4.x).  
**Do not** fall back to community Kuadrant or to vLLM-on-MaaS TP.

## Kuadrant Ready stuck / MissingDependency

Restart the kuadrant-operator pod once (Istio webhook race), then:
```bash
oc wait --for=condition=Ready kuadrant/kuadrant -n kuadrant-system --timeout=300s
oc get pods -n kuadrant-system
```

## ModelsAsAServiceReady stays False

1. Confirm DSC fields:
   ```bash
   oc get dsc default-dsc -o jsonpath='{.spec.components.aigateway}{"\n"}'
   ```
2. Confirm `maas-default-gateway` Programmed and annotations present.
3. Confirm `maas-db-config` exists in infra ns (`oc get maastenantconfig -A` / `infra_namespace` helper).
4. Confirm UWM pods Running.
5. `oc logs -n <infra-ns> deploy/maas-api --tail=100` (no secret dump).

## LLMInferenceService pods ImagePullBackOff

Simulator pulls from `ghcr.io`. If the sandbox blocks GHCR, either mirror the image to a reachable registry and patch the LLMIS image, or report blocker — do not switch to ExternalModel.

## LLMInferenceService Pending (GPU)

If you switched the manifest to request `nvidia.com/gpu: 1` while `llama-32-3b-instruct` still runs, the pod will Pending. Free the GPU with owner approval or keep the CPU simulator.

## MaaSModelRef not Ready

```bash
oc describe maasmodelref demo-simulator -n rhoai-maas-demo
oc get llminferenceservice demo-simulator -n rhoai-maas-demo
```
Backend must exist in the **same** namespace; `spec.modelRef.kind` must be `LLMInferenceService`.

## Gateway conflicts

Never edit `openshift-ai-inference` or `data-science-gateway`. Demo 1 uses dedicated `maas-default-gateway` + `openshift-default` GatewayClass.

## Accidental Demo 2 objects

If `MaaSSubscription` / `MaaSAuthPolicy` were applied earlier, leave them or delete only if labeled for this demo — they are not required for Demo 1 success.
