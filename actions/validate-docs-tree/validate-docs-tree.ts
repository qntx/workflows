import { spawnSync } from 'node:child_process';
import {
  existsSync,
  lstatSync,
  readdirSync,
  readFileSync,
  realpathSync,
  statSync,
} from 'node:fs';
import {
  dirname,
  extname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from 'node:path';
import { load as loadYaml } from 'js-yaml';

const IMAGE_EXT = new Set(['.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp']);
const ALLOWED_EXT = new Set(['.mdx', '.txt', ...IMAGE_EXT]);
const ALLOWED_COMPONENTS = new Set([
  'Callout',
  'Card',
  'Cards',
  'Tabs',
  'Tab',
  'Accordions',
  'Accordion',
  'Files',
  'Folder',
  'File',
  'ImageZoom',
  'TypeTable',
  'Steps',
  'Step',
]);
const SKIP_NAMES = new Set(['.DS_Store', 'node_modules', '.git', '.github']);
const TREE_BYTES = 20 * 1024 * 1024;
const FILE_BYTES = 2 * 1024 * 1024;
const MARKDOWNLINT_MISSING =
  'markdownlint-cli2 not found (set MARKDOWNLINT_CLI2 or bun install in this directory)';
const USAGE = `usage: bun validate-docs-tree.ts <docs-dir> [--lint]
       bun validate-docs-tree.ts --lint
         # action mode: GITHUB_WORKSPACE + WORKDIR + DOCS_PATH`;

export type ValidateResult = { ok: boolean; errors: string[] };

export type ValidateOptions = {
  markdownlintConfig?: string;
};

export type JailResult =
  | { ok: true; root: string }
  | { ok: false; errors: string[] };

function isInside(root: string, candidate: string): boolean {
  const rel = relative(root, candidate);
  return rel === '' || (!rel.startsWith(`..${sep}`) && rel !== '..');
}

function hasDotDot(p: string): boolean {
  return p
    .replace(/\\/g, '/')
    .split('/')
    .some((part) => part === '..');
}

export function resolveDocsRoot(
  workspace: string,
  workingDirectory: string,
  docsPath: string,
): JailResult {
  if (!workspace) {
    return { ok: false, errors: ['workspace missing or not a directory'] };
  }
  let workspaceReal: string;
  try {
    workspaceReal = realpathSync(workspace);
    if (!statSync(workspaceReal).isDirectory()) {
      return { ok: false, errors: ['workspace missing or not a directory'] };
    }
  } catch {
    return { ok: false, errors: ['workspace missing or not a directory'] };
  }

  const wd = workingDirectory || '.';
  const docs = docsPath || 'docs';

  if (isAbsolute(wd)) {
    return { ok: false, errors: ['working-directory must be relative'] };
  }
  if (isAbsolute(docs)) {
    return { ok: false, errors: ['docs-path must be relative'] };
  }
  if (hasDotDot(wd)) {
    return { ok: false, errors: ['working-directory must not contain ..'] };
  }
  if (hasDotDot(docs)) {
    return { ok: false, errors: ['docs-path must not contain ..'] };
  }

  const candidate = join(workspaceReal, wd, docs);
  let joined: string;
  try {
    joined = realpathSync(candidate);
  } catch {
    return { ok: false, errors: [`docs tree missing: ${candidate}`] };
  }
  if (joined !== workspaceReal && !joined.startsWith(workspaceReal + sep)) {
    return { ok: false, errors: ['docs-path escapes workspace'] };
  }
  try {
    if (!statSync(joined).isDirectory()) {
      return { ok: false, errors: [`docs tree missing: ${joined}`] };
    }
  } catch {
    return { ok: false, errors: [`docs tree missing: ${joined}`] };
  }
  return { ok: true, root: joined };
}

function stripFences(src: string): string {
  return src.replace(/~~~[\s\S]*?~~~/g, '').replace(/```[\s\S]*?```/g, '');
}

function walk(root: string): string[] {
  const out: string[] = [];
  const stack = [root];
  while (stack.length > 0) {
    const dir = stack.pop()!;
    for (const ent of readdirSync(dir, { withFileTypes: true })) {
      if (SKIP_NAMES.has(ent.name)) continue;
      const p = join(dir, ent.name);
      if (ent.isSymbolicLink() || lstatSync(p).isSymbolicLink()) {
        out.push(p);
        continue;
      }
      if (ent.isDirectory()) stack.push(p);
      else out.push(p);
    }
  }
  return out;
}

function parseFrontmatter(
  body: string,
): { title?: unknown; description?: unknown; full?: unknown } | null {
  if (!body.startsWith('---')) return null;
  const end = body.indexOf('\n---', 3);
  if (end < 0) return null;
  let parsed: unknown;
  try {
    parsed = loadYaml(body.slice(3, end));
  } catch {
    return null;
  }
  if (parsed === null || parsed === undefined) return {};
  if (typeof parsed !== 'object' || Array.isArray(parsed)) return null;
  const obj = parsed as Record<string, unknown>;
  return {
    title: obj.title,
    description: obj.description,
    full: obj.full,
  };
}

function pageExists(root: string, slug: string): boolean {
  return (
    existsSync(join(root, `${slug}.mdx`)) ||
    existsSync(join(root, slug, 'index.mdx')) ||
    existsSync(join(root, slug))
  );
}

function resolveMarkdownlintCli2(): { bin: string } | { error: string } {
  const envBin = process.env.MARKDOWNLINT_CLI2;
  if (envBin) {
    if (!existsSync(envBin)) return { error: MARKDOWNLINT_MISSING };
    return { bin: envBin };
  }
  const local = resolve(
    import.meta.dir,
    'node_modules',
    '.bin',
    'markdownlint-cli2',
  );
  if (existsSync(local)) return { bin: local };
  return { bin: 'markdownlint-cli2' };
}

export function validateDocsTree(
  rootInput: string,
  opts: ValidateOptions = {},
): ValidateResult {
  const errors: string[] = [];
  const root = resolve(rootInput);

  let rootStat;
  try {
    rootStat = lstatSync(root);
  } catch {
    return { ok: false, errors: [`missing tree: ${root}`] };
  }
  if (rootStat.isSymbolicLink()) {
    return { ok: false, errors: ['tree root must not be a symlink'] };
  }
  if (!rootStat.isDirectory()) {
    return { ok: false, errors: ['tree root must be a directory'] };
  }

  const files = walk(root);
  let total = 0;
  for (const p of files) {
    const rel = relative(root, p);
    const parts = rel.split(sep);
    if (parts.includes('.git') || parts.includes('.github')) {
      errors.push(`forbidden path segment: ${rel}`);
    }
    const st = lstatSync(p);
    if (st.isSymbolicLink()) {
      errors.push(`symlink rejected: ${rel}`);
      continue;
    }
    if (st.size > FILE_BYTES)
      errors.push(`file too large (${st.size}): ${rel}`);
    total += st.size;
    const base = parts[parts.length - 1] ?? '';
    const ext = extname(base);
    if (base === 'meta.json') continue;
    if (!ALLOWED_EXT.has(ext)) errors.push(`extension not allowed: ${rel}`);
  }
  if (total > TREE_BYTES) errors.push(`tree too large (${total} bytes)`);

  const metaPath = join(root, 'meta.json');
  let meta: { title?: unknown; pages?: unknown; root?: unknown };
  try {
    meta = JSON.parse(readFileSync(metaPath, 'utf8')) as typeof meta;
  } catch {
    return {
      ok: false,
      errors: [...errors, 'missing or invalid docs/meta.json'],
    };
  }
  if (typeof meta.title !== 'string' || meta.title.length === 0) {
    errors.push('meta.json title must be a non-empty string');
  }
  if (!Array.isArray(meta.pages)) {
    errors.push('meta.json pages must be an array');
  } else {
    for (const entry of meta.pages) {
      if (typeof entry !== 'string') {
        errors.push('meta.json pages entries must be strings');
        continue;
      }
      if (/^---.*---$/.test(entry) || /^\[[^\]]+\]\([^)]+\)$/.test(entry))
        continue;
      if (!pageExists(root, entry))
        errors.push(`meta.json pages missing: ${entry}`);
    }
  }
  if (meta.root !== undefined && meta.root !== false) {
    errors.push('library docs must not set root:true');
  }

  if (!existsSync(join(root, 'index.mdx'))) {
    errors.push('missing docs/index.mdx');
  }

  for (const p of files) {
    if (lstatSync(p).isSymbolicLink()) continue;
    if (extname(p) !== '.mdx') continue;
    const rel = relative(root, p);
    const body = readFileSync(p, 'utf8');
    const fm = parseFrontmatter(body);
    if (!fm) {
      errors.push(`frontmatter required: ${rel}`);
      continue;
    }
    if (typeof fm.title !== 'string' || fm.title.trim().length === 0)
      errors.push(`frontmatter title required: ${rel}`);
    if (
      typeof fm.description !== 'string' ||
      fm.description.trim().length === 0
    )
      errors.push(`frontmatter description required: ${rel}`);
    if (fm.full === true) errors.push(`full: true rejected: ${rel}`);

    const stripped = stripFences(body.replace(/^---[\s\S]*?\n---/, ''));
    if (/(^|\n)\s*(import|export)\s/.test(stripped)) {
      errors.push(`ESM import/export outside fences: ${rel}`);
    }
    for (const m of stripped.matchAll(/<([A-Z][A-Za-z0-9]*)\b/g)) {
      const tag = m[1];
      if (!ALLOWED_COMPONENTS.has(tag))
        errors.push(`unknown MDX tag <${tag}>: ${rel}`);
    }
    if (
      stripped.includes('](/examples/') ||
      stripped.includes('src="/') ||
      stripped.includes("src={'/") ||
      stripped.includes('src={"/') ||
      stripped.includes('href="/') ||
      stripped.includes("href={'/") ||
      stripped.includes('href={"/')
    ) {
      errors.push(`root-absolute site path rejected: ${rel}`);
    }
    for (const m of stripped.matchAll(/<include\b[^>]*>([^<]*)<\/include>/gi)) {
      const target = m[1].trim();
      const resolved = resolve(dirname(p), target);
      let real: string;
      try {
        real = realpathSync(resolved);
      } catch {
        errors.push(`include target missing: ${rel} -> ${target}`);
        continue;
      }
      if (!isInside(root, real))
        errors.push(`include escapes tree: ${rel} -> ${target}`);
    }
  }

  if (opts.markdownlintConfig) {
    const mdx = files.filter(
      (p) => !lstatSync(p).isSymbolicLink() && extname(p) === '.mdx',
    );
    if (mdx.length > 0) {
      const resolved = resolveMarkdownlintCli2();
      if ('error' in resolved) {
        errors.push(resolved.error);
      } else {
        const r = spawnSync(
          resolved.bin,
          ['--config', opts.markdownlintConfig, ...mdx],
          {
            encoding: 'utf8',
          },
        );
        if (r.error && (r.error as NodeJS.ErrnoException).code === 'ENOENT') {
          errors.push(MARKDOWNLINT_MISSING);
        } else if (r.status !== 0) {
          const msg = (r.stdout || r.stderr || 'markdownlint failed').trim();
          errors.push(`markdownlint: ${msg}`);
        }
      }
    }
  }

  return { ok: errors.length === 0, errors };
}

function emitError(msg: string): void {
  if (process.env.GITHUB_ACTIONS === 'true') {
    console.error(`::error::${msg}`);
  } else {
    console.error(msg);
  }
}

function run(argv: string[]): number {
  let lint = false;
  let positional: string | undefined;
  for (const a of argv) {
    if (a === '--lint') {
      lint = true;
      continue;
    }
    if (a.startsWith('-')) {
      console.error(USAGE);
      return 2;
    }
    if (positional !== undefined) {
      console.error(USAGE);
      return 2;
    }
    positional = a;
  }

  const config = lint
    ? resolve(import.meta.dir, 'docs-tree.markdownlint.jsonc')
    : undefined;

  let root: string;
  if (positional !== undefined) {
    root = positional;
  } else {
    const workspace = process.env.GITHUB_WORKSPACE;
    if (!workspace) {
      console.error(USAGE);
      return 2;
    }
    const jailed = resolveDocsRoot(
      workspace,
      process.env.WORKDIR ?? '',
      process.env.DOCS_PATH ?? '',
    );
    if (!jailed.ok) {
      for (const e of jailed.errors) emitError(e);
      return 1;
    }
    root = jailed.root;
  }

  const result = validateDocsTree(root, { markdownlintConfig: config });
  for (const e of result.errors) emitError(e);
  return result.ok ? 0 : 1;
}

if (import.meta.main) {
  process.exit(run(process.argv.slice(2)));
}
