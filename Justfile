# Format all files with Prettier.
all: format

# Format all files with Prettier.
format:
    bun run format

# Check formatting without writing changes.
check:
    bun run format:check

# Lint markdown files.
markdownlint:
    bun run markdownlint

# Unit tests for private composite actions.
test-composites:
    bash actions/protect-sync-path/test.sh
    bash actions/parse-env-block/test.sh
    bash actions/apt-install/test.sh
    bash actions/ops-dependabot-enable/test.sh

# Lint all reusable and self workflows (requires actionlint on PATH).
actionlint:
    actionlint .github/workflows/*.yml

# Audit composites and all workflows (requires zizmor on PATH).
zizmor:
    zizmor --config .zizmor.yml --min-severity=medium actions .github/workflows

# Check SHA pins on all workflows and composites (requires pinact on PATH).
pinact:
    pinact run --check --verify-comment .github/workflows/*.yml actions/*/action.yml

# Local lint: prettier, markdownlint, composite tests.
lint: check markdownlint test-composites

# Show available recipes.
help:
    @echo "Available recipes:"
    @echo "  just                 - Run 'bun run format' (default)"
    @echo "  just format          - Format all files with Prettier"
    @echo "  just check           - Check formatting without writing changes"
    @echo "  just markdownlint    - Run markdownlint-cli2"
    @echo "  just test-composites - Run composite action unit tests"
    @echo "  just lint            - check + markdownlint + test-composites"
    @echo "  just actionlint      - Lint .github/workflows/*.yml with actionlint"
    @echo "  just zizmor          - Audit actions/ and .github/workflows/"
    @echo "  just pinact          - pinact run --check --verify-comment on the full tree"
    @echo "  just help            - Show this help message"
