# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#                              Inverter Makefile
#
# WARNING: This file is part of the git repo. DO NOT INCLUDE SENSITIVE DATA!
#
# The Inverter smart contracts project uses this Makefile to execute common
# tasks.
#
# The Makefile supports a help command, i.e. `make help`.
#
# Expected enviroment variables are defined in the `dev.env` file.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# -----------------------------------------------------------------------------
# Common

.PHONY: clean
clean: ## Remove build artifacts
	@forge clean

.PHONY: build
build: ## Build project
	@forge build

.PHONY: update
update: ## Update dependencies
	@forge update

.PHONY: test
test: ## Run whole testsuite
	@forge test -vvv

# -----------------------------------------------------------------------------
# Individual Component Tests

.PHONY: testProposal
testProposal: ## Run Proposal tests
	@forge test -vvv --match-contract "Proposal"

.PHONY: testModuleManager
testModuleManager: ## Run ModuleManager tests
	@forge test -vvv --match-contract "ModuleManager"

.PHONY: testModule
testModule: ## Run Module tests
	@forge test -vvv --match-contract "Module" --no-match-contract "Manager"

.PHONY: testFactories
testFactories: ## Run Factory tests
	@forge test -vvv --match-contract "Factory"

# --------------------------------------
# Modules Tests

.PHONY: testModuleMilestone
testModuleMilestone: ## Run Milestone module tests
	@forge test -vvv --match-contract "Milestone"

# -----------------------------------------------------------------------------
# Static Analyzers

.PHONY: analyze-slither
analyze-slither: ## Run slither analyzer against project
	@slither .

.PHONY: analyze-c4udit
analyze-c4udit: ## Run c4udit analyzer against project
	@c4udit src

# -----------------------------------------------------------------------------
# Reports

.PHONY: report-gas
report-gas: ## Print gas report and create gas snapshots file
	@forge snapshot
	@forge test --gas-report

.PHONY: report-cov
report-cov: ## Print coverage report and create lcov report file
	@forge coverage --report lcov
	@forge coverage

# -----------------------------------------------------------------------------
# Formatting

.PHONY: fmt
fmt: ## Format code
	@forge fmt

.PHONY: fmt-check
fmt-check: ## Check whether code formatted correctly
	@forge fmt --check

# -----------------------------------------------------------------------------
# Help Command

.PHONY: help
help:
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
