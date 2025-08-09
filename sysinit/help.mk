ifndef DEFAULT_GOAL
.DEFAULT_GOAL := help
endif

## ANSI color codes
COLOR_RESET=\033[0m
COLOR_BOLD=\033[1m
COLOR_CYAN=\033[36m

##@ General
.PHONY: help
help: ## Show this help message
	@echo
	@echo "Usage:"
	@echo "  make $(COLOR_CYAN)<target>$(COLOR_RESET)"
	@echo
	@awk 'BEGIN {FS = ":.*##"; section = ""} \
		/^##@/ { section = substr($$0, 5); printf "\n$(COLOR_BOLD)%s$(COLOR_RESET)\n", section; next } \
		/^[a-zA-Z0-9_-]+:.*##/ { printf "  $(COLOR_CYAN)%-18s$(COLOR_RESET) %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)
	@echo
