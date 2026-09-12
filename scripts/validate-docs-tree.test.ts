import { afterEach, describe, expect, test } from 'bun:test';
import { mkdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { validateDocsTree } from './validate-docs-tree';

const lintConfig = resolve(import.meta.dir, 'docs-tree.markdownlint.jsonc');
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
