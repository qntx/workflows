# Format all files with Prettier.
all: format

# Format all files with Prettier.
format:
    bun run format

# Check formatting without writing changes.
check:
    bun run format:check

# Show available recipes.
help:
    @echo "Available recipes:"
    @echo "  just          - Run 'bun run format' (default)"
    @echo "  just format   - Format all files with Prettier"
    @echo "  just check    - Check formatting without writing changes"
    @echo "  just help     - Show this help message"
