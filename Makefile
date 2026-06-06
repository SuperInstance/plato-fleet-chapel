# Makefile for Plato Fleet Chapel
# Chapel compiler wrapper — adjust CHPL if needed

CHPL ?= chpl
CHPL_FLAGS = --fast -O2
SRC = src/Ternary.chpl src/PlatoEngine.chpl src/FleetManager.chpl src/GrooveTracker.chpl src/main.chpl
TEST_SRC = test/tests.chpl src/Ternary.chpl src/PlatoEngine.chpl src/FleetManager.chpl src/GrooveTracker.chpl

.PHONY: all test clean run

all: plato-fleet

plato-fleet: $(SRC)
	$(CHPL) $(CHPL_FLAGS) -o $@ $(SRC)

test: plato-test
	./plato-test

plato-test: $(TEST_SRC)
	$(CHPL) $(CHPL_FLAGS) -o $@ $(TEST_SRC)

run: plato-fleet
	./plato-fleet

clean:
	rm -f plato-fleet plato-test

# Multi-locale execution (requires Chapel built with MPI/GASNet)
run-multilocale: plato-fleet
	./plato-fleet -nl 5

help:
	@echo "Plato Fleet Chapel — Makefile targets:"
	@echo "  all              Build the main simulation (default)"
	@echo "  test             Build and run unit tests"
	@echo "  run              Build and run main simulation"
	@echo "  run-multilocale  Run on 5 locales (requires multi-locale Chapel)"
	@echo "  clean            Remove build artifacts"
	@echo ""
	@echo "Set CHPL to your Chapel compiler if not in PATH:"
	@echo "  make CHPL=/opt/chapel/bin/linux64-x86_64/chpl"
