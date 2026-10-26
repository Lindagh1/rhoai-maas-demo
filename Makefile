## ============================================================================
## Active demos — this is what you want
## ============================================================================

.PHONY: demo1-audit demo1-prereqs demo1-enable-maas demo1-enable-observability \
        demo1-deploy-model \
        demo1-publish demo1-verify demo1-verify-twice demo1-cleanup \
        demo1-all demo1-pdf \
        demo2-detect-idp demo2-create-identity demo2-grant-access \
        demo2-setup demo2-audit demo2-verify demo2-test-inference \
        demo2-test-negative demo2-test-access demo2-test-rate-limit \
        demo2-check-usage demo2-verify-key demo2-cleanup-access \
        demo2-cleanup demo2-all \
        pdf

## --- Demo 1: native llm-d + MaaS ---
## See docs/GUIDE-INSTALLATION-DEMO1.md / docs/GUIDE-DEMO-LIVE.md

demo1-audit:
	@bash scripts/00-audit.sh

demo1-prereqs:
	@bash scripts/10-prerequisites.sh

demo1-enable-maas:
	@bash scripts/20-enable-maas.sh

# Click-ops observability: "Observe & Monitor -> Dashboard" (Cluster / Models
# tabs) natively in the OpenShift AI UI, backed by COO + OTel + Perses.
demo1-enable-observability:
	@bash scripts/25-enable-observability.sh

demo1-deploy-model:
	@bash scripts/30-deploy-native-model.sh

demo1-publish:
	@bash scripts/40-publish-maas.sh

demo1-verify:
	@bash scripts/50-verify.sh

demo1-verify-twice:
	@bash scripts/50-verify.sh && bash scripts/50-verify.sh

# Full install from a fresh sandbox (requires prior `oc login`).
# Includes observability so the RHOAI dashboard's Observe & Monitor tabs
# are ready before Demo 2.
demo1-all: demo1-audit demo1-prereqs demo1-enable-maas demo1-enable-observability demo1-deploy-model demo1-publish demo1-verify-twice

# Requires CONFIRM=yes, e.g.: make demo1-cleanup CONFIRM=yes
demo1-cleanup:
	@CONFIRM=$(CONFIRM) bash scripts/99-cleanup.sh

demo1-pdf:
	@bash scripts/generate_pdf.sh docs/GUIDE-INSTALLATION-DEMO1.md docs/GUIDE-DEMO-LIVE.md

## --- Demo 2: reproducible MaaS end-user journey ---
## See docs/demo2/ and docs/GUIDE-DEMO-LIVE-DEMO2.md
## All demo2-* targets are safe to re-run (idempotent) except
## demo2-cleanup / demo2-cleanup-access, which require CONFIRM=yes.

# Read-only: detects which IdP strategy this sandbox uses (htpasswd /
# in-cluster Keycloak / external OIDC such as Entra ID). Run this first
# on any new sandbox. See docs/demo2/09-auth-oidc-entra.md.
demo2-detect-idp:
	@bash scripts/demo2/00-detect-identity-provider.sh

# Creates the non-admin test identity (maas-demo2-user) and group
# (maas-demo2-developers), branching on the detected IdP strategy.
# Refuses to mutate an external/enterprise OIDC provider automatically.
demo2-create-identity:
	@bash scripts/demo2/01-create-test-identity.sh

# Admin path (Scenario B): creates/updates the MaaSSubscription(s) +
# MaaSAuthPolicy granting maas-demo2-developers access to Demo 1's model.
demo2-grant-access:
	@bash scripts/demo2/10-admin-grant-access.sh

# Full environment setup from a fresh sandbox (identity + access).
# Does NOT create API keys — that step is the real end-user dashboard
# flow (Scenario C), which cannot be safely scripted (secret capture).
demo2-setup: demo2-detect-idp demo2-create-identity demo2-grant-access

# Read-only consolidated audit: IdP strategy, identity, governance
# objects, model readiness, and which local secret files exist (never
# their values). Safe to run anytime.
demo2-audit:
	@bash scripts/demo2/05-audit.sh

# Consolidated post-setup verification: model Ready, governance objects
# Active, and both known API keys (if captured) still return 200.
demo2-verify:
	@bash scripts/demo2/60-verify-all.sh

# Scenario D: real OpenAI-compatible inference as maas-demo2-user.
# Requires secrets/demo2/maas-demo2-user.apikey (create via dashboard,
# Scenario C) or DEMO2_API_KEY / DEMO2_API_KEY_FILE.
demo2-test-inference:
	@bash scripts/demo2/20-test-inference.sh

# Scenario E: negative tests (403 no AuthPolicy, 403 no subscription,
# 429 rate-limit on the isolated 50-tokens/1m subscription). Mutates and
# always restores the governance objects (safe, bounded request count).
demo2-test-negative:
	@bash scripts/demo2/40-test-negative.sh

# Aliases for demo2-test-negative, matching the individual Scenario E
# sub-checks it performs (access-denial vs rate-limit specifically).
demo2-test-access: demo2-test-negative
demo2-test-rate-limit: demo2-test-negative

# Scenario F: usage visibility, admin (Limitador Prometheus metrics) vs
# non-admin (dashboard Subscriptions tab). Read-only, no secrets.
demo2-check-usage:
	@bash scripts/demo2/50-check-usage-visibility.sh

# Reusable, secret-safe key health check. Usage:
#   make demo2-verify-key KEYFILE=secrets/demo2/maas-demo2-user.apikey
#   EXPECT=revoked make demo2-verify-key KEYFILE=secrets/demo2/maas-demo2-user.apikey
demo2-verify-key:
	@bash scripts/demo2/30-verify-key-status.sh $(KEYFILE) $(EXPECT)

# Scenario-cleanup for the admin-granted governance objects ONLY
# (MaaSSubscription(s) + MaaSAuthPolicy). Leaves identity/group/model
# untouched. Requires explicit confirmation:
#   make demo2-cleanup-access CONFIRM=yes
demo2-cleanup-access:
	@CONFIRM=$(CONFIRM) bash scripts/demo2/99-cleanup-access.sh

# Alias matching the task spec's exact required target name:
#   make demo2-cleanup CONFIRM=yes
demo2-cleanup: demo2-cleanup-access

# Full reproducible run-through on a fresh sandbox, up to (but not
# including) the manual dashboard steps (Scenario C key creation) and
# destructive cleanup. Requires prior `oc login` as a cluster-admin.
demo2-all: demo2-setup demo2-verify demo2-check-usage

## --- Shared ---

# Regenerate all PDF guides (Demo 1 installation + Demo 1 live + Demo 2 live).
pdf:
	@bash scripts/generate_pdf.sh

## ============================================================================
## Historical / other sandbox demos (not part of Demo 1 or Demo 2)
## Kept for traceability — see README.md "Structure du dépôt" table.
## ============================================================================

.PHONY: install-rhoai-operator install-vscode-workbench-demo \
        install-fraud-detection-tutorial preflight bootstrap status \
        infer demo-auth demo-rate-limit validate test-idempotency cleanup

install-rhoai-operator:
	@./scripts/install-rhoai-operator.sh

install-vscode-workbench-demo:
	@./scripts/install-vscode-workbench-demo.sh

install-fraud-detection-tutorial:
	@./scripts/install-fraud-detection-tutorial.sh

preflight:
	@./scripts/preflight.sh

bootstrap:
	@./scripts/bootstrap.sh

status:
	@./scripts/status.sh

infer:
	@./scripts/infer.sh

demo-auth:
	@./scripts/demo-auth.sh

demo-rate-limit:
	@./scripts/demo-rate-limit.sh

validate:
	@./scripts/validate.sh

test-idempotency:
	@./scripts/test-idempotency.sh

cleanup:
	@./scripts/cleanup.sh
