.PHONY: install-rhoai-operator install-vscode-workbench-demo install-fraud-detection-tutorial preflight bootstrap status infer demo-auth demo-rate-limit validate test-idempotency cleanup pdf \
        demo1-audit demo1-prereqs demo1-enable-maas demo1-deploy-model demo1-publish demo1-verify demo1-verify-twice demo1-cleanup demo1-all demo1-pdf

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

pdf:
	@./scripts/generate_pdf.sh docs/DEMO_GUIDE.md

## --- Demo 1: native llm-d + MaaS (see CURSOR_PROMPT_DEMO1.md / docs/GUIDE-INSTALLATION-DEMO1.md) ---

demo1-audit:
	@bash scripts/00-audit.sh

demo1-prereqs:
	@bash scripts/10-prerequisites.sh

demo1-enable-maas:
	@bash scripts/20-enable-maas.sh

demo1-deploy-model:
	@bash scripts/30-deploy-native-model.sh

demo1-publish:
	@bash scripts/40-publish-maas.sh

demo1-verify:
	@bash scripts/50-verify.sh

demo1-verify-twice:
	@bash scripts/50-verify.sh && bash scripts/50-verify.sh

# Full install from a fresh sandbox (requires prior `oc login`).
demo1-all: demo1-audit demo1-prereqs demo1-enable-maas demo1-deploy-model demo1-publish demo1-verify-twice

# Requires CONFIRM=yes, e.g.: make demo1-cleanup CONFIRM=yes
demo1-cleanup:
	@CONFIRM=$(CONFIRM) bash scripts/99-cleanup.sh

demo1-pdf:
	@bash scripts/generate_pdf.sh docs/GUIDE-INSTALLATION-DEMO1.md docs/GUIDE-DEMO-LIVE.md
