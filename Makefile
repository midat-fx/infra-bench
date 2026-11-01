# make test: one kind cluster + LocalStack, validate every scenario, tear down.
# KEEP=1 leaves the cluster running; IDS="k8s-oom-crashloop ..." narrows the run.
JOBS ?= 3
IDS ?=

.PHONY: test up down validate list agent purge

test:
	@bash lib/cluster.sh up && python3 bench.py validate -j $(JOBS) $(IDS); rc=$$?; \
	  [ "$(KEEP)" = 1 ] || bash lib/cluster.sh down; exit $$rc

up:
	@bash lib/cluster.sh up

down:
	@bash lib/cluster.sh down

validate:
	@python3 bench.py validate -j $(JOBS) $(IDS)

list:
	@python3 bench.py list

# Remove cluster, LocalStack and every pinned image (frees ~3 GB).
purge:
	@PURGE=1 bash lib/cluster.sh down
