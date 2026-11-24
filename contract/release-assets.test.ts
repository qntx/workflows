import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadContract, parseAssetName } from './release-assets';

const contract = loadContract();

describe('examples.valid', () => {
  for (const ex of contract.examples.valid) {
    test(ex.name, () => {
      const res = parseAssetName(contract, ex.bin, ex.version, ex.name);
      expect<string>(res.kind).toBe(ex.kind);
      if (
        res.kind === 'archive' ||
        res.kind === 'sha256' ||
        res.kind === 'sbom'
      ) {
        expect<string | undefined>(res.target).toBe(ex.target);
        expect(res.variant).toBe(ex.variant);
      }
    });
  }
});

describe('examples.ignored', () => {
  for (const ex of contract.examples.ignored) {
    test(ex.name, () => {
      expect(parseAssetName(contract, ex.bin, ex.version, ex.name).kind).toBe(
        'ignored',
      );
    });
  }
});

describe('examples.invalid', () => {
  for (const ex of contract.examples.invalid) {
    test(ex.name, () => {
      const res = parseAssetName(contract, ex.bin, ex.version, ex.name);
      expect(res.kind).toBe('invalid');
      if (res.kind === 'invalid') {
        expect(res.reason.length).toBeGreaterThan(0);
      }
    });
  }
});

test('bin and version are validated against the contract patterns', () => {
  expect(() =>
    parseAssetName(contract, 'not a bin!', '1.0.0', 'SHA256SUMS'),
  ).toThrow();
  expect(() =>
    parseAssetName(contract, 'tool', 'not.a.version', 'SHA256SUMS'),
  ).toThrow();
});

// --- CLI -----------------------------------------------------------------

const cli = fileURLToPath(new URL('./release-assets.ts', import.meta.url));

function runCli(args: string[]): { code: number; out: string; err: string } {
  const proc = Bun.spawnSync(['bun', cli, ...args], {
    stdout: 'pipe',
    stderr: 'pipe',
  });
  return {
    code: proc.exitCode,
    out: proc.stdout.toString(),
    err: proc.stderr.toString(),
  };
}

describe('cli', () => {
  test('check accepts the nosfry v0.4.0 asset names', () => {
    const names = contract.examples.valid
      .filter((e) => e.bin === 'nosfry' && e.version === '0.4.0')
      .map((e) => e.name);
    const res = runCli([
      'check',
      '--bin',
      'nosfry',
      '--version',
      '0.4.0',
      ...names,
    ]);
    expect(res.code).toBe(0);
    expect(res.out).toContain(
      'ok archive aarch64-apple-darwin - nosfry-0.4.0-aarch64-apple-darwin.tar.gz',
    );
    expect(res.out).toContain('ok sha256 x86_64-unknown-linux-gnu onion');
    expect(res.out).toContain('ok aggregate - - SHA256SUMS');
  });

  test('check exits 1 on an ignored name', () => {
    const res = runCli([
      'check',
      '--bin',
      'nosfry',
      '--version',
      '0.4.0',
      'nosfry-0.4.0-aarch64-apple-darwin.tar.gz',
      'install.sh',
    ]);
    expect(res.code).toBe(1);
    expect(res.out).toContain('ignored install.sh');
  });

  test('check exits 1 on an invalid name', () => {
    const res = runCli([
      'check',
      '--bin',
      'nosfry',
      '--version',
      '0.4.0',
      'nosfry-0.4.0-x86_64-unknown-linux-gnu.zip',
    ]);
    expect(res.code).toBe(1);
    expect(res.out).toContain(
      'INVALID nosfry-0.4.0-x86_64-unknown-linux-gnu.zip',
    );
  });

  test('check parses basenames of path arguments', () => {
    const res = runCli([
      'check',
      '--bin',
      'nosfry',
      '--version',
      '0.4.0',
      'downloads/nosfry-0.4.0-aarch64-apple-darwin.tar.gz',
    ]);
    expect(res.code).toBe(0);
  });

  test('check without --bin/--version exits nonzero', () => {
    expect(runCli(['check', 'x']).code).toBe(2);
    expect(runCli([]).code).toBe(2);
  });

  test('triples prints one contract triple per line', () => {
    const res = runCli(['triples']);
    expect(res.code).toBe(0);
    const lines = res.out.trim().split('\n');
    expect(lines).toEqual(contract.targets.map((t) => t.triple));
  });
});

// --- drift guard against release-rust.yml ---------------------------------

interface ReleaseRust {
  planRun: string;
  packageRun: string;
  targetsDescription: string;
}

interface YamlDoc {
  [key: string]: unknown;
}

// Pull the plan run block, the Package run block and the targets input
// description out of release-rust.yml. Bun.YAML is preferred; a text
// extraction covers runtimes without it.
function loadReleaseRust(): ReleaseRust {
  const text = readFileSync(
    fileURLToPath(
      new URL('../.github/workflows/release-rust.yml', import.meta.url),
    ),
    'utf8',
  );
  const yaml = (Bun as unknown as { YAML?: { parse(source: string): YamlDoc } })
    .YAML;
  if (yaml !== undefined) {
    const doc = yaml.parse(text);
    // YAML 1.1 parsers may turn the `on:` key into boolean `true`.
    const on = (doc['on'] ?? doc['true']) as {
      workflow_call: { inputs: { targets: { description: string } } };
    };
    const jobs = doc['jobs'] as {
      plan: { steps: { id?: string; run?: string }[] };
      build: { steps: { name?: string; run?: string }[] };
    };
    const planRun = jobs.plan.steps.find((s) => s.id === 'plan')?.run;
    const packageRun = jobs.build.steps.find((s) => s.name === 'Package')?.run;
    if (planRun === undefined || packageRun === undefined) {
      throw new Error(
        'release-rust.yml: expected steps plan/plan and build/Package',
      );
    }
    return {
      planRun,
      packageRun,
      targetsDescription: on.workflow_call.inputs.targets.description,
    };
  }

  const blockAfter = (anchor: RegExp): string => {
    const start = text.search(anchor);
    if (start < 0) {
      throw new Error(`release-rust.yml: anchor not found: ${anchor}`);
    }
    const m = text.slice(start).match(/run:\s*\|\n((?:[ ]{9,}[^\n]*\n?)+)/);
    if (m === null || m[1] === undefined) {
      throw new Error(`release-rust.yml: no run block after ${anchor}`);
    }
    return m[1];
  };
  const desc = text.match(/\n\s*targets:\s*\n\s*description:\s*'([^']+)'/);
  if (desc === null || desc[1] === undefined) {
    throw new Error('release-rust.yml: targets description not found');
  }
  return {
    planRun: blockAfter(/\bid:\s*plan\b/),
    packageRun: blockAfter(/name:\s*Package\b/),
    targetsDescription: desc[1],
  };
}

// The plan run block enumerates every supported triple in a case: one arm
// per line (`x86_64-unknown-linux-gnu) os=...`) or a `a | b)` shared arm.
function caseArmTriples(runBlock: string): string[] {
  const found = new Set<string>();
  const arm =
    /^[ \t]*([A-Za-z0-9][A-Za-z0-9_-]*(?:[ \t]*\|[ \t]*[A-Za-z0-9][A-Za-z0-9_-]*)*)[ \t]*\)/gm;
  for (const m of runBlock.matchAll(arm)) {
    const group = m[1];
    if (group === undefined) {
      continue;
    }
    for (const part of group.split('|')) {
      found.add(part.trim());
    }
  }
  return [...found].sort();
}

const contractTriples = contract.targets.map((t) => t.triple).sort();

test('release-rust.yml plan case arms are exactly the contract triples', () => {
  const { planRun } = loadReleaseRust();
  expect(caseArmTriples(planRun)).toEqual(contractTriples);
});

test('the drift check detects a triple the contract does not list', () => {
  const { planRun } = loadReleaseRust();
  const drifted = planRun.replace(
    '    *)',
    "    riscv64gc-unknown-linux-gnu) os='ubuntu-24.04'; cross=true; musl=false ;;\n    *)",
  );
  expect(drifted).not.toBe(planRun);
  expect(caseArmTriples(drifted)).not.toEqual(contractTriples);
});

test('release-rust.yml targets description mentions every contract triple', () => {
  const { targetsDescription } = loadReleaseRust();
  for (const triple of contractTriples) {
    expect(targetsDescription).toContain(triple);
  }
});

test('the Package step archive rule agrees with each contract archive extension', () => {
  const { packageRun } = loadReleaseRust();
  // The rule under test: `*windows*` -> zip, everything else -> tar.gz.
  expect(packageRun).toContain('*windows*');
  expect(packageRun).toContain('.zip');
  expect(packageRun).toContain('.tar.gz');
  for (const { triple, archive } of contract.targets) {
    expect(triple.includes('windows') ? 'zip' : 'tar.gz').toBe(archive);
  }
});

test('layout lists members for exactly the archive extensions in use', () => {
  const contract = loadContract();
  const exts = [...new Set(contract.targets.map((t) => t.archive))].sort();
  expect(Object.keys(contract.layout.members).sort()).toEqual(exts);
});
