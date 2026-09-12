import { afterEach, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  mkdirSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { resolveDocsRoot, validateDocsTree } from './validate-docs-tree';

const lintConfig = resolve(import.meta.dir, 'docs-tree.markdownlint.jsonc');
const cli = resolve(import.meta.dir, 'validate-docs-tree.ts');
const temps: string[] = [];

function tree(files: Record<string, string>): string {
  const dir = join(tmpdir(), `docs-validate-${crypto.randomUUID()}`);
  mkdirSync(dir, { recursive: true });
  temps.push(dir);
  for (const [rel, body] of Object.entries(files)) {
    const p = join(dir, rel);
    mkdirSync(join(p, '..'), { recursive: true });
    writeFileSync(p, body);
  }
  return dir;
}

function runCli(
  args: string[],
  extraEnv: Record<string, string | undefined> = {},
) {
  const env = { ...process.env, ...extraEnv };
  for (const [k, v] of Object.entries(extraEnv)) {
    if (v === undefined) delete env[k];
  }
  return spawnSync(process.execPath, [cli, ...args], {
    encoding: 'utf8',
    env,
  });
}

afterEach(() => {
  for (const d of temps.splice(0)) rmSync(d, { recursive: true, force: true });
});

const okPage = `---
title: Index
description: A valid landing page.
---

Hello.
`;

const okMeta = JSON.stringify({ title: 'demo', pages: ['index'] }, null, 2);

describe('validateDocsTree', () => {
  test('accepts a minimal tree', () => {
    const dir = tree({ 'meta.json': okMeta, 'index.mdx': okPage });
    const r = validateDocsTree(dir);
    expect(r.errors).toEqual([]);
    expect(r.ok).toBe(true);
  });

  test('accepts a minimal tree with markdownlint', () => {
    const dir = tree({ 'meta.json': okMeta, 'index.mdx': okPage });
    const r = validateDocsTree(dir, { markdownlintConfig: lintConfig });
    expect(r.errors).toEqual([]);
    expect(r.ok).toBe(true);
  });

  test('rejects missing frontmatter', () => {
    const dir = tree({ 'meta.json': okMeta, 'index.mdx': 'no frontmatter\n' });
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('frontmatter'))).toBe(true);
  });

  test('rejects unknown tag Landing', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: Landing is forbidden.
---

<Landing title="no" />
`,
    });
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('<Landing>'))).toBe(true);
  });

  test('rejects full: true', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: Home chrome only.
full: true
---

Hi.
`,
    });
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('full: true'))).toBe(true);
  });

  test('rejects ESM import outside fences', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: No imports.
---

import x from './x.js'
`,
    });
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('import/export'))).toBe(true);
  });

  test('allows import inside fences', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: Fenced import is fine.
---

\`\`\`ts
import x from './x.js'
\`\`\`
`,
    });
    expect(validateDocsTree(dir).ok).toBe(true);
  });

  test('rejects include that escapes the tree', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: Jail.
---

<include>../outside.md</include>
`,
    });
    writeFileSync(join(dir, '..', 'outside.md'), 'nope\n');
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('include'))).toBe(true);
  });

  test('rejects symlink', () => {
    const dir = tree({ 'meta.json': okMeta, 'index.mdx': okPage });
    symlinkSync(join(dir, 'index.mdx'), join(dir, 'link.mdx'));
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('symlink'))).toBe(true);
  });

  test('rejects .ts files', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': okPage,
      'helper.ts': 'export {}',
    });
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('helper.ts'))).toBe(true);
  });

  test('rejects root: true', () => {
    const dir = tree({
      'meta.json': JSON.stringify({
        title: 'demo',
        pages: ['index'],
        root: true,
      }),
      'index.mdx': okPage,
    });
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('root'))).toBe(true);
  });

  test('rejects missing pages slug', () => {
    const dir = tree({
      'meta.json': JSON.stringify({ title: 'demo', pages: ['index', 'usage'] }),
      'index.mdx': okPage,
    });
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('usage'))).toBe(true);
  });

  test('rejects root-absolute /examples/ markdown link', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: No site public paths.
---

See [x](/examples/diagram.svg).
`,
    });
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('root-absolute'))).toBe(true);
  });

  test('rejects src="/ site path', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: No site public paths.
---

<ImageZoom src="/examples/diagram.svg" />
`,
    });
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('root-absolute'))).toBe(true);
  });

  test("rejects src={'/ site path", () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: No site public paths.
---

<ImageZoom src={'/examples/diagram.svg'} />
`,
    });
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('root-absolute'))).toBe(true);
  });

  test('rejects src={"/ ImageZoom double-quote', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: No site public paths.
---

<ImageZoom src={"/examples/diagram.svg"} />
`,
    });
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('root-absolute'))).toBe(true);
  });

  test('markdownlint MD040 on untagged fence', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: Fence language required.
---

\`\`\`
untagged
\`\`\`
`,
    });
    const r = validateDocsTree(dir, { markdownlintConfig: lintConfig });
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('markdownlint'))).toBe(true);
  });

  test('markdownlint binary missing is fail-closed', () => {
    const prev = process.env.MARKDOWNLINT_CLI2;
    process.env.MARKDOWNLINT_CLI2 = join(tmpdir(), 'no-such-markdownlint-cli2');
    try {
      const dir = tree({ 'meta.json': okMeta, 'index.mdx': okPage });
      const r = validateDocsTree(dir, { markdownlintConfig: lintConfig });
      expect(r.ok).toBe(false);
      expect(
        r.errors.some((e) => e.includes('markdownlint-cli2 not found')),
      ).toBe(true);
    } finally {
      if (prev === undefined) delete process.env.MARKDOWNLINT_CLI2;
      else process.env.MARKDOWNLINT_CLI2 = prev;
    }
  });
});

describe('resolveDocsRoot', () => {
  test("('.', 'docs') under a temp workspace is ok", () => {
    const ws = tree({ 'docs/index.mdx': okPage, 'docs/meta.json': okMeta });
    const r = resolveDocsRoot(ws, '.', 'docs');
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.root).toBe(realpathSync(join(ws, 'docs')));
  });

  test('nested relative docs-path is ok', () => {
    const rel = 'actions/validate-docs-tree/fixtures/valid-docs';
    const ws = tree({
      [`${rel}/index.mdx`]: okPage,
      [`${rel}/meta.json`]: okMeta,
    });
    const r = resolveDocsRoot(ws, '.', rel);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.root).toBe(realpathSync(join(ws, rel)));
  });

  test('absolute docs-path fails', () => {
    const ws = tree({ 'docs/index.mdx': okPage });
    const r = resolveDocsRoot(ws, '.', '/etc');
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.errors.some((e) => e.includes('relative'))).toBe(true);
  });

  test('.. in either input fails', () => {
    const ws = tree({ 'docs/index.mdx': okPage });
    const wd = resolveDocsRoot(ws, '..', 'docs');
    const docs = resolveDocsRoot(ws, '.', '../docs');
    const nested = resolveDocsRoot(ws, 'foo/../docs', 'docs');
    expect(wd.ok).toBe(false);
    expect(docs.ok).toBe(false);
    expect(nested.ok).toBe(false);
  });

  test('joined path outside workspace fails', () => {
    const ws = tree({});
    const outside = tree({ 'index.mdx': okPage });
    symlinkSync(outside, join(ws, 'docs'));
    const r = resolveDocsRoot(ws, '.', 'docs');
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.errors.some((e) => e.includes('escapes'))).toBe(true);
  });

  test('missing directory is ok:false and does not throw', () => {
    const ws = tree({});
    let r: ReturnType<typeof resolveDocsRoot> | undefined;
    expect(() => {
      r = resolveDocsRoot(ws, '.', 'docs');
    }).not.toThrow();
    expect(r?.ok).toBe(false);
    if (r && !r.ok)
      expect(r.errors.some((e) => e.includes('docs tree missing'))).toBe(true);
  });

  test('file instead of directory is ok:false and does not throw', () => {
    const ws = tree({ docs: 'not a directory\n' });
    let r: ReturnType<typeof resolveDocsRoot> | undefined;
    expect(() => {
      r = resolveDocsRoot(ws, '.', 'docs');
    }).not.toThrow();
    expect(r?.ok).toBe(false);
    if (r && !r.ok)
      expect(r.errors.some((e) => e.includes('docs tree missing'))).toBe(true);
  });

  test('empty inputs normalize to . / docs', () => {
    const ws = tree({ 'docs/index.mdx': okPage, 'docs/meta.json': okMeta });
    const r = resolveDocsRoot(ws, '', '');
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.root).toBe(realpathSync(join(ws, 'docs')));
  });

  test('symlink workspace is followed, not rejected', () => {
    const real = tree({
      'docs/index.mdx': okPage,
      'docs/meta.json': okMeta,
    });
    const link = join(tmpdir(), `docs-validate-${crypto.randomUUID()}`);
    symlinkSync(real, link);
    temps.push(link);
    const r = resolveDocsRoot(link, '.', 'docs');
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.root).toBe(realpathSync(join(real, 'docs')));
  });
});

describe('frontmatter YAML', () => {
  test('full: "true" (quoted string) is accepted', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: Quoted full is a string.
full: "true"
---

Hi.
`,
    });
    const r = validateDocsTree(dir);
    expect(r.errors).toEqual([]);
    expect(r.ok).toBe(true);
  });

  test('invalid YAML in --- block is frontmatter required', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: [unclosed
description: Broken.
---

Hi.
`,
    });
    const r = validateDocsTree(dir);
    expect(r.ok).toBe(false);
    expect(r.errors.some((e) => e.includes('frontmatter required'))).toBe(true);
  });

  test('extra keys are ignored', () => {
    const dir = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: Extra keys are ignored.
sidebar: false
---

Hi.
`,
    });
    const r = validateDocsTree(dir);
    expect(r.errors).toEqual([]);
    expect(r.ok).toBe(true);
  });

  test('title and description must be non-empty strings', () => {
    const emptyTitle = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: ""
description: Empty title.
---

Hi.
`,
    });
    const numberTitle = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: 1
description: Numeric title.
---

Hi.
`,
    });
    const missingDesc = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
---

Hi.
`,
    });
    const numberDesc = tree({
      'meta.json': okMeta,
      'index.mdx': `---
title: Index
description: 1
---

Hi.
`,
    });
    expect(validateDocsTree(emptyTitle).ok).toBe(false);
    expect(validateDocsTree(numberTitle).ok).toBe(false);
    expect(validateDocsTree(missingDesc).ok).toBe(false);
    expect(validateDocsTree(numberDesc).ok).toBe(false);
    expect(
      validateDocsTree(emptyTitle).errors.some((e) => e.includes('title')),
    ).toBe(true);
    expect(
      validateDocsTree(numberTitle).errors.some((e) => e.includes('title')),
    ).toBe(true);
    expect(
      validateDocsTree(missingDesc).errors.some((e) =>
        e.includes('description'),
      ),
    ).toBe(true);
    expect(
      validateDocsTree(numberDesc).errors.some((e) =>
        e.includes('description'),
      ),
    ).toBe(true);
  });
});

describe('CLI', () => {
  test('--lint without positional and without GITHUB_WORKSPACE exits 2', () => {
    const r = runCli(['--lint'], { GITHUB_WORKSPACE: undefined });
    expect(r.status).toBe(2);
    expect(r.stderr).toContain('usage:');
  });
});
