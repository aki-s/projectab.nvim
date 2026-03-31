.PHONY: test lint lint-fix

test:
	nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }"

lint:
	stylua --check .

lint-fix:
	stylua .
