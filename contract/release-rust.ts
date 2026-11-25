import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// --- drift guard against release-rust.yml ---------------------------------

export interface ReleaseRust {
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
export function loadReleaseRust(): ReleaseRust {
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
export function caseArmTriples(runBlock: string): string[] {
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
