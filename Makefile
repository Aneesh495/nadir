MMC = mmc
PYTHON = python3
BIN_DIR = bin
SRC_DIR = src
TESTS_DIR = tests
BENCH_DIR = benchmarks

.PHONY: all clean test bench verify sim

all: $(BIN_DIR)/nadir

$(BIN_DIR)/nadir:
	mkdir -p $(BIN_DIR)
	cd $(SRC_DIR) && $(MMC) --make nadir
	cp $(SRC_DIR)/nadir $(BIN_DIR)/nadir

test: all
	@echo "Running verification checks..."
	$(PYTHON) scripts/verify_no_em_dashes.py
	@echo "Running test suite..."
	cd $(TESTS_DIR) && $(MMC) --make test_runner && ./test_runner
	$(PYTHON) -m unittest discover -s tests -p "test_*.py"

bench: all
	@echo "Running performance microbenchmarks..."
	cd $(BENCH_DIR) && $(MMC) --make bench_runner && ./bench_runner

sim: all
	$(BIN_DIR)/nadir simulate --demo

verify: test
	@echo "Complete verification suite passed with zero errors."

clean:
	rm -rf $(BIN_DIR)
	rm -rf $(SRC_DIR)/Mercury $(SRC_DIR)/nadir
	rm -rf $(TESTS_DIR)/Mercury $(TESTS_DIR)/test_runner
	rm -rf $(BENCH_DIR)/Mercury $(BENCH_DIR)/bench_runner
	find . -name "*.mh" -delete
	find . -name "*.err" -delete
	find . -name "*.init" -delete
