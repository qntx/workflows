import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadContract, parseAssetName } from './release-assets';
import { caseArmTriples, loadReleaseRust } from './release-rust';

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
// loadReleaseRust and caseArmTriples live in ./release-rust (shared with
// release-rust-plan.test.ts).

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

// --- Package step produces the canonical archive layout --------------------
//
// Instead of string-matching release-rust.yml, run the extracted Package run
// block with bash in a scratch directory (fake build output, LICENSE, README)
// and inspect the archives it writes. The canonical member is the one
// `layout.members` entry without a `<stem>/` prefix; the `<stem>/` entries
// exist only for releases made outside release-rust.

const FIXTURE_BIN = 'fixture-bin';
const FIXTURE_VERSION = '1.2.3';

function canonicalMember(ext: string): string {
  const flat = contract.layout.members[ext].filter(
    (m) => !m.startsWith('<stem>/'),
  );
  expect(flat).toHaveLength(1);
  return flat[0] as string;
}

interface Packaged {
  stem: string;
  ext: string;
  distFiles: string[];
  members: string[];
}

function runPackageStep(
  runBlock: string,
  triple: string,
  variant: string,
): Packaged {
  const work = mkdtempSync(join(tmpdir(), 'pkg-'));
  const shim = mkdtempSync(join(tmpdir(), 'shim-'));
  try {
    const ext = contract.targets.find((t) => t.triple === triple)?.archive;
    if (ext === undefined) {
      throw new Error(`no contract target ${triple}`);
    }
    const exe = triple.includes('windows') ? `${FIXTURE_BIN}.exe` : FIXTURE_BIN;
    const binDir = join(work, 'target', triple, 'release');
    mkdirSync(binDir, { recursive: true });
    writeFileSync(join(binDir, exe), 'fixture\n');
    writeFileSync(join(work, 'LICENSE'), 'MIT\n');
    writeFileSync(join(work, 'README.md'), 'fixture\n');

    // 7z is not on every runner. The shim implements only `7z a <archive>
    // <dir>` by writing the sorted list of regular files under <dir>
    // (relative) to <archive> as text; the test reads it back as the zip
    // member list.
    writeFileSync(
      join(shim, '7z'),
      [
        '#!/usr/bin/env bash',
        'set -euo pipefail',
        '[[ "$1" == a ]] || { echo "7z shim: unsupported: $*" >&2; exit 2; }',
        'find "$3" -type f | while IFS= read -r f; do',
        '  printf \'%s\\n\' "${f#./}"',
        'done | sort >"$2"',
        '',
      ].join('\n'),
    );
    chmodSync(join(shim, '7z'), 0o755);

    const proc = spawnSync('bash', ['-c', runBlock], {
      cwd: work,
      env: {
        ...process.env,
        BIN: FIXTURE_BIN,
        TARGET: triple,
        VARIANT: variant,
        GITHUB_REF_NAME: `v${FIXTURE_VERSION}`,
        PATH: `${shim}:${process.env.PATH}`,
      },
      encoding: 'utf8',
    });
    if (proc.status !== 0) {
      throw new Error(
        `Package run block exited ${proc.status}:\n${proc.stdout}\n${proc.stderr}`,
      );
    }

    const stem = `${FIXTURE_BIN}-${FIXTURE_VERSION}${variant === '' ? '' : `-${variant}`}-${triple}`;
    const archive = join(work, 'dist', `${stem}.${ext}`);
    let members: string[];
    if (ext === 'tar.gz') {
      const list = spawnSync('tar', ['tzf', archive], { encoding: 'utf8' });
      if (list.status !== 0) {
        throw new Error(`tar tzf failed: ${list.stderr}`);
      }
      members = list.stdout.split('\n').filter((l) => l !== '');
    } else {
      members = readFileSync(archive, 'utf8')
        .split('\n')
        .filter((l) => l !== '');
    }
    return {
      stem,
      ext,
      distFiles: readdirSync(join(work, 'dist')),
      members,
    };
  } finally {
    rmSync(work, { recursive: true, force: true });
    rmSync(shim, { recursive: true, force: true });
  }
}

describe('Package step layout', () => {
  const { packageRun } = loadReleaseRust();

  test('the run block only uses env vars, so it can run outside Actions', () => {
    expect(packageRun).not.toContain('${{');
  });

  const cases = [
    { triple: 'x86_64-unknown-linux-gnu', variant: '' },
    { triple: 'x86_64-unknown-linux-gnu', variant: 'extra' },
    { triple: 'x86_64-pc-windows-msvc', variant: '' },
  ];
  for (const { triple, variant } of cases) {
    test(`${triple} (variant ${variant === '' ? 'none' : variant}) produces the canonical flat layout`, () => {
      const { stem, ext, distFiles, members } = runPackageStep(
        packageRun,
        triple,
        variant,
      );
      const name = `${stem}.${ext}`;
      expect(distFiles).toContain(name);
      expect(distFiles).toContain(`${name}.sha256`);

      const parsed = parseAssetName(
        contract,
        FIXTURE_BIN,
        FIXTURE_VERSION,
        name,
      );
      expect(parsed.kind).toBe('archive');
      if (parsed.kind === 'archive' || parsed.kind === 'sha256') {
        expect(parsed.target).toBe(triple);
        expect(parsed.variant).toBe(variant === '' ? null : variant);
      }

      const canonical = canonicalMember(ext).replace('<bin>', FIXTURE_BIN);
      expect(members).toContain(canonical);
      for (const m of members) {
        expect(m.startsWith(`${stem}/`)).toBe(false);
        expect(m.startsWith(`./${stem}/`)).toBe(false);
      }
      const root = ext === 'zip' ? '' : './';
      expect(members).toContain(`${root}LICENSE`);
      expect(members).toContain(`${root}README.md`);
    });
  }

  test('the check bites: a top-level-directory tar is not canonical', () => {
    const drifted = packageRun.replace(
      'tar czf "dist/$staging.tar.gz" -C "$staging" .',
      'tar czf "dist/$staging.tar.gz" "$staging"',
    );
    expect(drifted).not.toBe(packageRun);
    const { stem, members } = runPackageStep(
      drifted,
      'x86_64-unknown-linux-gnu',
      '',
    );
    expect(members).toContain(`${stem}/${FIXTURE_BIN}`);
    expect(members).not.toContain(
      canonicalMember('tar.gz').replace('<bin>', FIXTURE_BIN),
    );
  });
});
