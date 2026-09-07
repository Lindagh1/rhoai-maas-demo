.PHONY: install-rhoai-operator preflight bootstrap status infer demo-auth demo-rate-limit validate test-idempotency cleanup pdf

install-rhoai-operator:
	@./scripts/install-rhoai-operator.sh

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
