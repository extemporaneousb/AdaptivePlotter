.PHONY: build test check strict-check

SWIFT_FLAGS ?=

build:
	swift build $(SWIFT_FLAGS)

test:
	swift test --parallel $(SWIFT_FLAGS)

check: build test
	@sh Scripts/check_repository_contract.sh
	@if test -f Scripts/validate_evidence_manifest.sh; then bash Scripts/validate_evidence_manifest.sh; fi
	@git diff --check

strict-check:
	@$(MAKE) check SWIFT_FLAGS='-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors'
