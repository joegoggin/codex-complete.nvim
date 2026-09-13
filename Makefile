MINI_NVIM_VERSION := v0.18.0

.PHONY: deps test format lint check

deps:
	@test -d .deps/mini.nvim || git clone --depth 1 --branch $(MINI_NVIM_VERSION) https://github.com/nvim-mini/mini.nvim.git .deps/mini.nvim

test: deps
	nvim --headless --noplugin -u tests/minimal_init.lua -c 'lua MiniTest.run()'

format:
	stylua lua plugin tests

lint:
	stylua --check lua plugin tests
	selene lua plugin tests

check: lint test
