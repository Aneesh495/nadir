MMC = mmc
PYTHON = python3
BIN_DIR = bin
SRC_DIR = src
TESTS_DIR = tests
BENCH_DIR = benchmarks

.PHONY: all clean test bench verify sim build test-regression test-properties lint

all: build

build:
	mkdir -p $(BIN_DIR)
	cd $(SRC_DIR) && $(MMC) --make nadir
	cp $(SRC_DIR)/nadir $(BIN_DIR)/nadir
	cd $(SRC_DIR) && $(MMC) --make test_runner
	cp $(SRC_DIR)/test_runner $(BIN_DIR)/test_runner
	cd $(SRC_DIR) && $(MMC) --make bench_runner
	cp $(SRC_DIR)/bench_runner $(BIN_DIR)/bench_runner

lint:
	@echo "Verifying absence of forbidden dashes..."
	$(PYTHON) scripts/verify_no_em_dashes.py

test-regression: all
	@echo "Running astrodynamics regression suite..."
	$(PYTHON) -m unittest tests/test_regression.py

test-properties: all
	@echo "Running property-based invariant test suite..."
	$(PYTHON) -m unittest tests/test_astrodynamics_properties.py

test: lint all test-regression test-properties
	@echo "Running Mercury test runner..."
	$(BIN_DIR)/test_runner
	@echo "Running full Python test discovery suite..."
	$(PYTHON) -m unittest discover -s tests -p "test_*.py"

bench: all
	@echo "Running performance microbenchmarks..."
	$(BIN_DIR)/bench_runner

sim: all
	$(BIN_DIR)/nadir simulate --demo

verify: test
	@echo "Complete verification suite passed with zero errors."

clean:
	rm -rf $(BIN_DIR)
	rm -rf $(SRC_DIR)/Mercury $(SRC_DIR)/nadir $(SRC_DIR)/test_runner $(SRC_DIR)/bench_runner
	rm -rf $(TESTS_DIR)/Mercury $(TESTS_DIR)/test_runner
	rm -rf $(BENCH_DIR)/Mercury $(BENCH_DIR)/bench_runner
	find . -name "*.mh" -delete
	find . -name "*.err" -delete
	find . -name "*.init" -delete
