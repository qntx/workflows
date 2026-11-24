# fixture-bun-gates

Self-CI fixture for the independent-gates proof. The `lint` and `typecheck`
scripts exit 1 on purpose so the `e2e-bun-gates` job has two red gates while
`build` and `test` still pass; the failure is intentional, do not fix it.
