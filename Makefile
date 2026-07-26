BUNDLE_ID ?= com.yourname.Wetools
DEV_INSTALL_PATH ?= /Applications/Wetools Dev.app

.PHONY: run install test reset release-local

run:
	BUNDLE_ID="$(BUNDLE_ID)" INSTALL_APP="$(DEV_INSTALL_PATH)" SIGNING_SCENARIO=local-dev ./scripts/dev_install.sh Debug

install:
	BUNDLE_ID="$(BUNDLE_ID)" INSTALL_APP="$(DEV_INSTALL_PATH)" SIGNING_SCENARIO=local-dev ./scripts/dev_install.sh Debug

test:
	./scripts/dev_test.sh

reset:
	./scripts/dev_reset.sh

release-local:
	@if [ -x ./scripts/release_local.sh ]; then \
		BUNDLE_ID="$(BUNDLE_ID)" SIGNING_SCENARIO=github-release ./scripts/release_local.sh; \
	elif [ -x ./scripts/local_release_check.sh ]; then \
		BUNDLE_ID="$(BUNDLE_ID)" SIGNING_SCENARIO=github-release ./scripts/local_release_check.sh; \
	else \
		echo "No local release preflight script found."; \
	fi
