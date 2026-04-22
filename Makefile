.PHONY: all format check help

all: format

format:
	bun run format

check:
	bun run format:check

help:
	@echo "Available targets:"
	@echo "  make          - Run 'bun run format' (default)"
	@echo "  make format   - Format all files with Prettier"
	@echo "  make check    - Check formatting without writing changes"
	@echo "  make help     - Show this help message"
