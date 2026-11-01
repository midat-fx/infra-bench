# make test: one kind cluster + LocalStack, validate every scenario, tear down.
# KEEP=1 leaves the cluster running; IDS="k8s-oom-crashloop ..." narrows the run.
JOBS ?= 3
IDS ?=

.PHONY: test policy-test up down validate list agent purge

test: policy-test
	@bash lib/cluster.sh up && python3 bench.py validate -j $(JOBS) $(IDS); rc=$$?; \
	  [ "$(KEEP)" = 1 ] || bash lib/cluster.sh down; exit $$rc

# Rego unit tests only: no cluster, a few seconds.
policy-test:
	@bash lib/policy-test.sh

up:
	@bash lib/cluster.sh up

down:
	@bash lib/cluster.sh down

validate:
	@python3 bench.py validate -j $(JOBS) $(IDS)

list:
	@python3 bench.py list

# Remove cluster, LocalStack, every pinned image and the provider cache.
purge:
	@PURGE=1 bash lib/cluster.sh down
