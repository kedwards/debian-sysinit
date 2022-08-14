mkfile_path:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

REAL_BRANCH_NAME=$(shell git rev-parse --abbrev-ref HEAD)
ifeq ($(BRANCH_NAME),)
	BRANCH_NAME=$(REAL_BRANCH_NAME)
endif
EXTRA_VARS_BRANCH="--extra-vars='branch_name=$(BRANCH_NAME)'"

ifdef VARS
  EXTRA_VARS="--extra-vars='$(VARS)'"
endif

ifdef TAG
  TAGS=--tag=$(TAG)
endif

ifneq ($(PASS),)
	PASS_FILE="--vault-password-file='$(PASS)'"
endif

DEFAULT_GOAL := help

##@ [Targets]
help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

deps: ## Install dependencies, ex. make deps
	@pip3 install -r requirements.txt && \
	GO111MODULE=on go get github.com/awslabs/aws-cloudformation-template-formatter/cmd/cfn-format && \
	ansible-galaxy collection install --force -r requirements.yml

run: guard-PLAY guard-ENV ## Run ansible playbook, ex. make run ENV=play PLAY=devops
	@echo ansible-playbook \
		--inventory-file=inventory \
		--extra-vars=env_tag=$(ENV) $(EXTRA_VARS_BRANCH) $(EXTRA_VARS) $(TAGS) $(PASS_FILE) \
		project/${PLAY}.yml

guard-%:
	@if [ "${${*}}" = "" ]; then \
  echo "Variable $* not set"; \
  exit 1; \
  fi

lint: ## Lint ansible files, ex. make lint
	@./lint.sh

.PHONY: deps deploy guard help lint
