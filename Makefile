# make test: one kind cluster + LocalStack, validate every scenario, tear down.
# KEEP=1 leaves the cluster running; IDS="k8s-oom-crashloop ..." narrows the run.
JOBS ?= 3
IDS ?=

.PHONY: test check policy-test up down validate list agent purge

test: policy-test
	@bash lib/cluster.sh up && python3 bench.py validate -j $(JOBS) $(IDS); rc=$$?; \
	  [ "$(KEEP)" = 1 ] || bash lib/cluster.sh down; exit $$rc

# Everything that needs no cluster, run before every push and in CI.
SCRIPTS = lib/*.sh scenarios/*/*.sh scenarios/*/wrong/*/_post.sh
check: policy-test
	@for f in $(SCRIPTS); do bash -n "$$f" || exit 1; done
	@python3 -m unittest -q test_bench
	@bash lib/leak-check.sh

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
