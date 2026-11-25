import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadReleaseRust } from './release-rust';

// Runs the extracted plan run block with bash, the way the plan job does.
// GITHUB_OUTPUT goes to a temp file; the raw `matrix=` line is returned
// verbatim so the golden comparison is byte-exact.

interface PlanEnv {
  TARGETS: string;
  VARIANTS: string;
  SMOKE_COMMAND: string;
  GLIBC_FLOOR: string;
  CROSS_PACKAGES: string;
}

interface PlanResult {
  code: number;
  output: string;
  matrixLine: string | null;
}

// The workflow's input defaults.
const DEFAULT_ENV: PlanEnv = {
  TARGETS:
    'x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu aarch64-apple-darwin x86_64-pc-windows-msvc aarch64-pc-windows-msvc',
  VARIANTS: '',
  SMOKE_COMMAND: '',
  GLIBC_FLOOR: '',
  CROSS_PACKAGES: 'gcc-aarch64-linux-gnu',
};

const { planRun } = loadReleaseRust();

function runPlan(env: Partial<PlanEnv>): PlanResult {
  const dir = mkdtempSync(join(tmpdir(), 'plan-'));
  try {
    const outFile = join(dir, 'github-output');
    writeFileSync(outFile, '');
    const proc = spawnSync('bash', ['-c', planRun], {
      env: {
        ...process.env,
        ...DEFAULT_ENV,
        ...env,
        GITHUB_OUTPUT: outFile,
      },
      encoding: 'utf8',
    });
    const matrixLine =
      readFileSync(outFile, 'utf8')
        .split('\n')
        .find((l) => l.startsWith('matrix=')) ?? null;
    return {
      code: proc.status ?? -1,
      output: `${proc.stdout}${proc.stderr}`,
      matrixLine,
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

interface MatrixEntry {
  target: string;
  os: string;
  smoke_os: string;
  variant: string;
  features: string;
  cross?: boolean;
  musl?: boolean;
  zig?: boolean;
}

function matrixEntries(matrixLine: string): MatrixEntry[] {
  const parsed = JSON.parse(matrixLine.slice('matrix='.length)) as {
    include: MatrixEntry[];
  };
  return parsed.include;
}

function goldenEntries(output: string): MatrixEntry[] {
  return matrixEntries(output);
}

interface GoldenCase {
  name: string;
  env: { TARGETS: string; VARIANTS: string; SMOKE_COMMAND: string };
  output: string;
}

const golden = JSON.parse(
  readFileSync(
    fileURLToPath(
      new URL('./fixtures/release-rust-plan.golden.json', import.meta.url),
    ),
    'utf8',
  ),
) as GoldenCase[];

// Golden `matrix=` lines were generated from main's plan block (git show
// 0b8a72a:.github/workflows/release-rust.yml). String equality here is the
// proof that an unset glibc-floor leaves the plan output — and therefore
// the job graph, job names, check names and artifact names — byte-identical
// for the ~150 callers pinned to a release tag.
describe('golden: empty glibc-floor is byte-identical to main', () => {
  for (const g of golden) {
    test(g.name, () => {
      const res = runPlan(g.env);
      expect(res.code).toBe(0);
      expect(res.matrixLine).toBe(g.output);
    });
  }
});

describe('glibc-floor matrix', () => {
  test('default five: gnu entries get zig:true and lose cross, others match golden', () => {
    const res = runPlan({ GLIBC_FLOOR: '2.31' });
    expect(res.code).toBe(0);
    expect(res.matrixLine).not.toBeNull();
    const include = matrixEntries(res.matrixLine as string);
    const base = goldenEntries(
      (golden.find((g) => g.name === 'default five targets') as GoldenCase)
        .output,
    );
    for (const e of include) {
      const goldenEntry = base.find((x) => x.target === e.target);
      expect(goldenEntry).toBeDefined();
      const ge = goldenEntry as MatrixEntry;
      if (e.target.endsWith('-unknown-linux-gnu')) {
        expect(e.zig).toBe(true);
        expect('cross' in e).toBe(false);
        const { zig: _zig, ...rest } = e;
        // aarch64-gnu has cross:true on main; the zig build drops it.
        const { cross: _cross, ...goldenRest } = ge;
        expect(rest).toEqual(goldenRest);
      } else {
        expect('zig' in e).toBe(false);
        expect(e).toEqual(ge);
      }
    }
  });

  test('all seven: musl entries have no zig and equal golden', () => {
    const allSeven = golden.find((g) => g.name === 'all seven triples');
    const res = runPlan({
      TARGETS: (allSeven as GoldenCase).env.TARGETS,
      GLIBC_FLOOR: '2.31',
    });
    expect(res.code).toBe(0);
    const include = matrixEntries(res.matrixLine as string);
    const base = goldenEntries((allSeven as GoldenCase).output);
    const musl = include.filter((e) => e.target.endsWith('-musl'));
    expect(musl).toHaveLength(2);
    for (const e of musl) {
      expect('zig' in e).toBe(false);
      const goldenEntry = base.find((x) => x.target === e.target);
      expect(goldenEntry).toBeDefined();
      expect(e).toEqual(goldenEntry as MatrixEntry);
    }
  });

  test('variants: all four gnu entries get zig, windows gets none', () => {
    const g = golden.find(
      (x) => x.name === 'two gnu plus windows with variant and smoke',
    ) as GoldenCase;
    const res = runPlan({ ...g.env, GLIBC_FLOOR: '2.31' });
    expect(res.code).toBe(0);
    const include = matrixEntries(res.matrixLine as string);
    expect(include).toHaveLength(6);
    const gnu = include.filter((e) => e.target.endsWith('-unknown-linux-gnu'));
    const windows = include.filter((e) => e.target.endsWith('-windows-msvc'));
    expect(gnu).toHaveLength(4);
    for (const e of gnu) {
      expect(e.zig).toBe(true);
      expect('cross' in e).toBe(false);
    }
    expect(windows).toHaveLength(2);
    for (const e of windows) {
      expect('zig' in e).toBe(false);
    }
  });
});

describe('glibc-floor validation', () => {
  for (const floor of ['2', '2.31.1', 'v2.31']) {
    test(`rejects malformed floor ${floor}`, () => {
      const res = runPlan({ GLIBC_FLOOR: floor });
      expect(res.code).not.toBe(0);
      expect(res.output).toContain(
        `::error::invalid glibc-floor: ${floor} (expected MAJOR.MINOR, e.g. 2.31)`,
      );
    });
  }

  for (const floor of ['2.16', '3.0']) {
    test(`rejects out-of-range floor ${floor}`, () => {
      const res = runPlan({ GLIBC_FLOOR: floor });
      expect(res.code).not.toBe(0);
      expect(res.output).toContain(
        `::error::unsupported glibc-floor: ${floor} (expected 2.17 or newer within glibc 2.x`,
      );
    });
  }

  test('rejects a floor when targets has no gnu triple', () => {
    const res = runPlan({
      TARGETS: 'aarch64-apple-darwin',
      GLIBC_FLOOR: '2.31',
    });
    expect(res.code).not.toBe(0);
    expect(res.output).toContain(
      '::error::glibc-floor is set but targets has no *-unknown-linux-gnu triple',
    );
  });

  test('rejects non-default cross-packages under a floor', () => {
    const res = runPlan({
      GLIBC_FLOOR: '2.31',
      CROSS_PACKAGES: 'gcc-aarch64-linux-gnu libssl-dev:arm64',
    });
    expect(res.code).not.toBe(0);
    expect(res.output).toContain(
      '::error::cross-packages is not used under glibc-floor',
    );
  });

  test('floor 2.17 (the Rust minimum) is accepted', () => {
    const res = runPlan({ GLIBC_FLOOR: '2.17' });
    expect(res.code).toBe(0);
  });
});
