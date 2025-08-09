include help.mk

##@ Build
build: ## Build the project
	@echo "Building..."

clean: ## Remove build artifacts
	rm -rf dist
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -delete
	find . -name "*.tmp" -delete

lint: ## Run all linting checks
	pre-commit run --all-files

lint-ansible: ## Lint Ansible code
	ansible-lint playbook.yml roles/

lint-shell: ## Run shellcheck only
	find . -name "*.sh" -type f -not -path "./.venv/*" | xargs shellcheck -e SC1091

##@ Testing
test: ## Run ansible syntax check
	ansible-playbook --syntax-check playbook.yml

molecule-test: ## Run Molecule tests for default scenario, no destroy
	cd roles/sysinit && molecule test --destroy=never

molecule-converge: ## Run Molecule converge for development
	cd roles/sysinit && molecule converge

molecule-verify: ## Run Molecule verify only
	cd roles/sysinit && molecule verify

molecule-destroy: ## Destroy Molecule test instances
	cd roles/sysinit && molecule destroy

##@ Secrets
scan-secrets: ## Scan for secrets
	detect-secrets scan --baseline .secrets.baseline --force-use-all-plugins

update-secrets: ## Update secrets baseline
	detect-secrets scan --baseline .secrets.baseline --force-use-all-plugins

audit-secrets: ## Audit secrets baseline
	detect-secrets audit .secrets.baseline

##@ Utility
install-deps: ## Install development dependencies
	uv pip install -e . --group dev
	@echo "Please also install shellcheck using your system package manager:"
	@echo "  Ubuntu/Debian: sudo apt install shellcheck"
	@echo "  macOS: brew install shellcheck"
	@echo "  Arch Linux: sudo pacman -S shellcheck"

install-hooks: ## Install pre-commit hooks
	pre-commit install
