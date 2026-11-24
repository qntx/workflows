// Parser for the qntx/release-assets naming contract (release-assets.json).
// Grammar: <bin>-<version>[-<variant>]-<target>.<ext>
// See docs/RELEASE-ASSETS.md. Zero runtime dependencies.

import { readFileSync } from 'node:fs';
import { basename } from 'node:path';
import { fileURLToPath } from 'node:url';

export interface ContractPattern {
  bin: string;
  version: string;
  variant: string;
}

export interface ContractTarget {
  triple: string;
  archive: string;
}

export interface ContractAsset {
  kind: string;
  name: string;
  required: boolean;
  description: string;
}

export interface ContractExample {
  bin: string;
  version: string;
  name: string;
  kind: string;
  target?: string;
  variant: string | null;
  reason?: string;
}

export interface Contract {
  contract: string;
  version: number;
  description: string;
  grammar: string;
  patterns: ContractPattern;
  targets: ContractTarget[];
  assets: ContractAsset[];
  rules: string[];
  layout: {
    description: string;
    members: Record<string, string[]>;
  };
  examples: {
    valid: ContractExample[];
    ignored: ContractExample[];
    invalid: ContractExample[];
  };
}

export type ParsedAsset =
  | {
      kind: 'archive' | 'sha256' | 'sbom';
      target: string;
      variant: string | null;
    }
  | { kind: 'aggregate' }
  | { kind: 'ignored' }
  | { kind: 'invalid'; reason: string };

export function loadContract(path?: string): Contract {
  const file =
    path ?? fileURLToPath(new URL('./release-assets.json', import.meta.url));
  return JSON.parse(readFileSync(file, 'utf8')) as Contract;
}

function invalid(reason: string): ParsedAsset {
  return { kind: 'invalid', reason };
}

export function parseAssetName(
  contract: Contract,
  bin: string,
  version: string,
  name: string,
): ParsedAsset {
  const binRe = new RegExp(contract.patterns.bin);
  const versionRe = new RegExp(contract.patterns.version);
  const variantRe = new RegExp(contract.patterns.variant);
  if (!binRe.test(bin)) {
    throw new Error(
      `bin does not match ${contract.patterns.bin}: ${JSON.stringify(bin)}`,
    );
  }
  if (!versionRe.test(version)) {
    throw new Error(
      `version does not match ${contract.patterns.version}: ${JSON.stringify(version)}`,
    );
  }

  if (name === 'SHA256SUMS') {
    return { kind: 'aggregate' };
  }

  const prefix = `${bin}-${version}-`;
  if (!name.startsWith(prefix)) {
    return { kind: 'ignored' };
  }
  const rest = name.slice(prefix.length);

  // Archive extensions known to the contract, longest first so a compound
  // extension (tar.gz) is never cut short by a single-segment one.
  const archives = [...new Set(contract.targets.map((t) => t.archive))].sort(
    (a, b) => b.length - a.length,
  );

  let kind: 'archive' | 'sha256' | 'sbom';
  let archive: string | null;
  let stem: string;
  if (rest.endsWith('.cdx.json')) {
    kind = 'sbom';
    archive = null;
    stem = rest.slice(0, -'.cdx.json'.length);
  } else if (rest.endsWith('.sha256')) {
    const inner = rest.slice(0, -'.sha256'.length);
    const ext = archives.find((a) => inner.endsWith(`.${a}`));
    if (ext === undefined) {
      return invalid(
        'the .sha256 sidecar is named after the archive: <name>.<archive>.sha256',
      );
    }
    kind = 'sha256';
    archive = ext;
    stem = inner.slice(0, -(ext.length + 1));
  } else {
    const ext = archives.find((a) => rest.endsWith(`.${a}`));
    if (ext === undefined) {
      return invalid(`no recognized archive or sidecar extension: ${name}`);
    }
    kind = 'archive';
    archive = ext;
    stem = rest.slice(0, -(ext.length + 1));
  }

  // The stem is '<target>' or '<variant>-<target>', the triple matched as a
  // suffix with a '-' boundary. No contract triple is a suffix of another,
  // but longest-first keeps the match unambiguous anyway.
  const triples = contract.targets
    .map((t) => t.triple)
    .sort((a, b) => b.length - a.length);
  let target: string | null = null;
  let variant: string | null = null;
  for (const triple of triples) {
    if (stem === triple) {
      target = triple;
      break;
    }
    if (stem.endsWith(`-${triple}`)) {
      target = triple;
      variant = stem.slice(0, stem.length - triple.length - 1);
      break;
    }
  }
  if (target === null) {
    return invalid(`no known target triple in stem '${stem}'`);
  }
  if (variant !== null && !variantRe.test(variant)) {
    return invalid(
      `variant '${variant}' does not match ${contract.patterns.variant}`,
    );
  }

  if (archive !== null) {
    const expected = contract.targets.find((t) => t.triple === target)?.archive;
    if (archive !== expected) {
      return invalid(`${target} releases use .${expected}, not .${archive}`);
    }
  }
  return { kind, target, variant };
}

function usage(): never {
  process.stderr.write(
    'usage: release-assets.ts check --bin <bin> --version <version> <file-or-name>...\n' +
      '       release-assets.ts triples\n',
  );
  process.exit(2);
}

function main(argv: string[]): void {
  const command = argv[0];
  if (command === 'triples') {
    const contract = loadContract();
    for (const { triple } of contract.targets) {
      console.log(triple);
    }
    return;
  }
  if (command !== 'check') {
    usage();
  }

  let bin: string | undefined;
  let version: string | undefined;
  const names: string[] = [];
  const args = argv.slice(1);
  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i] as string;
    if (arg === '--bin' || arg === '--version') {
      const value = args[i + 1];
      if (value === undefined) {
        usage();
      }
      if (arg === '--bin') {
        bin = value;
      } else {
        version = value;
      }
      i += 1;
    } else if (arg.startsWith('--')) {
      usage();
    } else {
      names.push(arg);
    }
  }
  if (bin === undefined || version === undefined) {
    usage();
  }

  const contract = loadContract();
  let bad = 0;
  for (const arg of names) {
    const name = basename(arg);
    const result = parseAssetName(contract, bin, version, name);
    switch (result.kind) {
      case 'ignored':
        console.log(`ignored ${name}`);
        bad += 1;
        break;
      case 'invalid':
        console.log(`INVALID ${name}: ${result.reason}`);
        bad += 1;
        break;
      case 'aggregate':
        console.log(`ok aggregate - - ${name}`);
        break;
      default:
        console.log(
          `ok ${result.kind} ${result.target} ${result.variant ?? '-'} ${name}`,
        );
    }
  }
  // A release dist directory is fully inside the namespace: ignored names
  // are drift just like invalid ones, so both fail the check.
  if (bad > 0) {
    process.exit(1);
  }
}

if (import.meta.main) {
  main(process.argv.slice(2));
}
