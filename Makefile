.PHONY: test lint lint-fix

test:
	# -i NONE: Prevents ShaDa read/write (fixes Vim:E576 errors during concurrent/headless tests)
	nvim --headless --noplugin -i NONE -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }"

lint:
	stylua --check .

lint-fix:
	stylua .
