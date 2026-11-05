.PHONY: publish publish-verify publish-cleanup \
        govern-login govern-user govern govern-setup govern-audit \
        save-key govern-verify call show-denials usage check-key \
        govern-cleanup pdf

## Publier — deploy an LLM and publish it on MaaS.
## See GUIDE.md

publish:
	@bash scripts/publish/00-audit.sh
	@bash scripts/publish/10-prerequisites.sh
	@bash scripts/publish/20-enable-platform.sh
	@bash scripts/publish/25-observability.sh
	@bash scripts/publish/30-deploy-llm.sh
	@bash scripts/publish/40-publish.sh
	@bash scripts/publish/50-verify.sh

publish-verify:
	@bash scripts/publish/50-verify.sh

# Requires CONFIRM=yes
publish-cleanup:
	@CONFIRM=$(CONFIRM) bash scripts/publish/99-cleanup.sh

## Gouverner — who can call the model, and how many tokens.
## See GUIDE.md

govern-login:
	@bash scripts/govern/00-detect-login.sh

govern-user:
	@bash scripts/govern/01-create-user.sh

govern:
	@bash scripts/govern/10-grant.sh

govern-setup: govern-login govern-user govern

govern-audit:
	@bash scripts/govern/05-audit.sh

save-key:
	@bash scripts/govern/21-save-key.sh

govern-verify:
	@bash scripts/govern/60-verify.sh

call:
	@bash scripts/govern/20-call.sh

show-denials:
	@bash scripts/govern/40-show-denials.sh

usage:
	@bash scripts/govern/50-usage.sh

#   make check-key KEYFILE=secrets/demo-user.apikey
#   EXPECT=revoked make check-key KEYFILE=secrets/demo-user.apikey
check-key:
	@bash scripts/govern/30-check-key.sh $(KEYFILE) $(EXPECT)

# Requires CONFIRM=yes
govern-cleanup:
	@CONFIRM=$(CONFIRM) bash scripts/govern/99-cleanup.sh

pdf:
	@bash scripts/generate_pdf.sh

.PHONY: prepare demo validate traffic quota-test live-reset endpoints
prepare:
	@bash scripts/prepare.sh
demo:
	@bash scripts/bootstrap.sh
validate:
	@bash scripts/validate.sh
traffic:
	@bash scripts/govern/20-call.sh --count 5 --output evidence/traffic.json
quota-test:
	@bash scripts/govern/20-call.sh --key-file secrets/demo-user.ratelimit.apikey --count 5 --expect-429 --output evidence/quota.json
live-reset:
	@CONFIRM=$(CONFIRM) bash scripts/reset-live.sh
endpoints:
	@bash scripts/endpoints.sh
