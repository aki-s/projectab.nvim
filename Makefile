.PHONY: test lint lint-fix

TEST_VERBOSE ?= 0

test:
# -i NONE: Prevents ShaDa read/write (fixes Vim:E576 errors during concurrent/headless tests)
#	nvim --headless --noplugin -i NONE -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', timeout = 5000 } "
	@out=$$(nvim --headless --noplugin -i NONE -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua', timeout = 5000 }" 2>&1); \
	status=$$?; \
	if [ "$$TEST_VERBOSE" = "1" ] || [ $$status -ne 0 ]; then \
		printf "$$out"; \
	else \
		echo "$$out" | sed -n 's/^Testing:[[:space:]]*//p'; \
	fi; \
	exit $$status

testv:
	TEST_VERBOSE=1 make test

lint:
	stylua --check .

lint-fix:
	stylua .
