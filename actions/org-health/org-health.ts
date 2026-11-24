// Maintains the single "Org health" issue in qntx/workflows listing the
// active workflows whose latest completed push/schedule run on the default
// branch is failing. Read-mostly: every code path is GET except the issue
// create/patch, which never runs under DRY_RUN.

import { appendFileSync } from 'node:fs';

export const ISSUE_TITLE = 'Org health';
export const MARKER = '<!-- qntx/workflows org-health -->';
const RUN_EVENTS = new Set(['push', 'schedule']);
const IGNORED_CONCLUSIONS = new Set([
  'cancelled',
  'skipped',
  'neutral',
  'stale',
  'action_required',
]);
const FAILING_CONCLUSIONS = new Set([
  'failure',
  'timed_out',
  'startup_failure',
]);

export type FetchLike = (
  input: string | URL,
  init?: RequestInit,
) => Promise<Response>;

export interface Repo {
  name: string;
  default_branch: string;
  archived: boolean;
  private: boolean;
}

export interface Workflow {
  id: number;
  name: string;
  state: string;
}

export interface WorkflowRun {
  event: string;
  head_branch: string;
  conclusion: string | null;
  created_at: string;
  html_url: string;
}

export interface Issue {
  number: number;
  title: string;
  state: string;
  body: string | null;
  pull_request?: unknown;
}

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

function headers(token: string): Record<string, string> {
  return {
    accept: 'application/vnd.github+json',
    authorization: `Bearer ${token}`,
    'x-github-api-version': '2022-11-28',
  };
}

function noteRateLimit(res: Response, url: string): void {
  if (res.status === 403 || res.status === 429) {
    const remaining = res.headers.get('x-ratelimit-remaining');
    console.error(
      `rate limit: GET ${url} -> ${res.status} (x-ratelimit-remaining=${remaining ?? 'unknown'})`,
    );
  }
}

async function apiGet(
  f: FetchLike,
  url: string,
  token: string,
): Promise<Response> {
  const res = await f(url, { method: 'GET', headers: headers(token) });
  if (!res.ok) {
    noteRateLimit(res, url);
    throw new ApiError(res.status, `GET ${url} -> ${res.status}`);
  }
  return res;
}

export function parseNextLink(header: string | null): string | null {
  if (header === null) {
    return null;
  }
  for (const part of header.split(',')) {
    const m = /<([^>]+)>\s*;\s*rel="([^"]+)"/.exec(part);
    if (m !== null && m[2] === 'next') {
      return m[1] ?? null;
    }
  }
  return null;
}

function unwrapList(data: unknown): unknown[] {
  if (Array.isArray(data)) {
    return data;
  }
  if (data !== null && typeof data === 'object') {
    for (const key of ['workflows', 'workflow_runs', 'items']) {
      const value = (data as Record<string, unknown>)[key];
      if (Array.isArray(value)) {
        return value;
      }
    }
  }
  return [];
}

async function apiGetAll(
  f: FetchLike,
  url: string,
  token: string,
): Promise<unknown[]> {
  const out: unknown[] = [];
  let next: string | null = url;
  while (next !== null) {
    const res = await apiGet(f, next, token);
    out.push(...unwrapList(await res.json()));
    next = parseNextLink(res.headers.get('link'));
  }
  return out;
}

export async function listRepos(
  f: FetchLike,
  apiUrl: string,
  org: string,
  token: string,
): Promise<Repo[]> {
  const repos = (await apiGetAll(
    f,
    `${apiUrl}/orgs/${org}/repos?type=public&per_page=100`,
    token,
  )) as Repo[];
  return repos
    .filter((r) => r.archived === false && r.private === false)
    .sort((a, b) => a.name.localeCompare(b.name));
}

export async function listActiveWorkflows(
  f: FetchLike,
  apiUrl: string,
  owner: string,
  repo: string,
  token: string,
): Promise<Workflow[]> {
  const workflows = (await apiGetAll(
    f,
    `${apiUrl}/repos/${owner}/${repo}/actions/workflows?per_page=100`,
    token,
  )) as Workflow[];
  return workflows.filter((w) => w.state === 'active');
}

export async function latestRuns(
  f: FetchLike,
  apiUrl: string,
  owner: string,
  repo: string,
  workflowId: number,
  branch: string,
  token: string,
): Promise<WorkflowRun[]> {
  const res = await apiGet(
    f,
    `${apiUrl}/repos/${owner}/${repo}/actions/workflows/${workflowId}/runs?branch=${encodeURIComponent(branch)}&status=completed&per_page=100`,
    token,
  );
  const data = (await res.json()) as { workflow_runs?: WorkflowRun[] };
  return (data.workflow_runs ?? []).filter(
    (r) => RUN_EVENTS.has(r.event) && r.head_branch === branch,
  );
}

export interface Streak {
  failing: boolean;
  consecutive: number;
  /** true when no success was found inside the fetched page. */
  bounded: boolean;
  failingSince: string | null;
  url: string | null;
}

// runs must be newest first (the API's order).
export function summarizeStreak(runs: WorkflowRun[]): Streak {
  let consecutive = 0;
  let url: string | null = null;
  let failingSince: string | null = null;
  for (const run of runs) {
    const conclusion = run.conclusion;
    if (conclusion === null || IGNORED_CONCLUSIONS.has(conclusion)) {
      continue;
    }
    if (FAILING_CONCLUSIONS.has(conclusion)) {
      consecutive += 1;
      if (url === null) {
        url = run.html_url;
      }
      failingSince = run.created_at;
      continue;
    }
    if (conclusion === 'success') {
      return {
        failing: consecutive > 0,
        consecutive,
        bounded: false,
        failingSince,
        url,
      };
    }
    // Unknown conclusions neither break the streak nor count as failures.
  }
  return {
    failing: consecutive > 0,
    consecutive,
    bounded: true,
    failingSince,
    url,
  };
}

export interface FailRow {
  repo: string;
  workflow: string;
  failingSince: string;
  consecutive: number;
  bounded: boolean;
  url: string;
}

export interface NotChecked {
  repo: string;
  status: number;
}

export function renderBody(input: {
  org: string;
  rows: FailRow[];
  notChecked: NotChecked[];
  now: Date;
  by: string;
}): string {
  const lines: string[] = [
    MARKER,
    '',
    `Public, non-archived repositories of \`${input.org}\`; the latest completed \`push\`/\`schedule\` run of each active workflow on the default branch.`,
    '',
    'Private repositories are out of scope: their Actions are currently blocked by billing.',
    '',
  ];
  if (input.rows.length === 0) {
    lines.push('No failing workflows.');
  } else {
    lines.push(
      '| Repository | Workflow | Failing since | Consecutive failures | Latest failing run |',
      '| --- | --- | --- | --- | --- |',
    );
    const sorted = [...input.rows].sort((a, b) =>
      a.repo === b.repo
        ? a.workflow.localeCompare(b.workflow)
        : a.repo.localeCompare(b.repo),
    );
    for (const row of sorted) {
      const since = `${row.bounded ? '≤' : ''}${row.failingSince.slice(0, 10)}`;
      const count = `${row.bounded ? '≥' : ''}${row.consecutive}`;
      lines.push(
        `| ${row.repo} | ${row.workflow} | ${since} | ${count} | [run](${row.url}) |`,
      );
    }
  }
  if (input.notChecked.length > 0) {
    lines.push('', 'Not checked:', '');
    for (const e of input.notChecked) {
      lines.push(`- ${e.repo} (HTTP ${e.status})`);
    }
  }
  lines.push('', `Updated ${input.now.toISOString()} by ${input.by}`, '');
  return lines.join('\n');
}

export interface ExistingIssue {
  number: number;
  state: string;
  body: string | null;
}

export type IssuePlan =
  | { action: 'create'; body: string }
  | { action: 'update' | 'reopen' | 'close'; number: number; body: string }
  | { action: 'none' };

export function stripUpdatedLine(body: string): string {
  return body
    .split('\n')
    .filter((line) => !line.startsWith('Updated '))
    .join('\n')
    .trimEnd();
}

export function planIssue(
  existing: ExistingIssue | null,
  failingCount: number,
  newBody: string,
): IssuePlan {
  if (existing === null) {
    return failingCount > 0
      ? { action: 'create', body: newBody }
      : { action: 'none' };
  }
  if (failingCount === 0) {
    return existing.state === 'open'
      ? { action: 'close', number: existing.number, body: newBody }
      : { action: 'none' };
  }
  if (existing.state !== 'open') {
    return { action: 'reopen', number: existing.number, body: newBody };
  }
  if (stripUpdatedLine(existing.body ?? '') === stripUpdatedLine(newBody)) {
    return { action: 'none' };
  }
  return { action: 'update', number: existing.number, body: newBody };
}

export async function findHealthIssue(
  f: FetchLike,
  apiUrl: string,
  repository: string,
  token: string,
): Promise<Issue | null> {
  const isHealthIssue = (i: Issue, requireMarker: boolean): boolean =>
    i.pull_request === undefined &&
    i.title === ISSUE_TITLE &&
    (!requireMarker || (typeof i.body === 'string' && i.body.includes(MARKER)));

  const creator = encodeURIComponent('github-actions[bot]');
  const botIssues = (await apiGetAll(
    f,
    `${apiUrl}/repos/${repository}/issues?state=all&per_page=100&creator=${creator}`,
    token,
  )) as Issue[];
  const own = botIssues.find((i) => isHealthIssue(i, false));
  if (own !== undefined) {
    return own;
  }
  const all = (await apiGetAll(
    f,
    `${apiUrl}/repos/${repository}/issues?state=all&per_page=100`,
    token,
  )) as Issue[];
  return all.find((i) => isHealthIssue(i, true)) ?? null;
}

async function apiWrite(
  f: FetchLike,
  method: 'POST' | 'PATCH',
  url: string,
  payload: Record<string, unknown>,
  token: string,
): Promise<void> {
  const res = await f(url, {
    method,
    headers: { ...headers(token), 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    noteRateLimit(res, url);
    throw new ApiError(res.status, `${method} ${url} -> ${res.status}`);
  }
}

export interface RunOptions {
  token: string;
  org: string;
  repository: string;
  apiUrl: string;
  dryRun: boolean;
  runUrl?: string;
  now?: Date;
  fetchImpl?: FetchLike;
  stepSummary?: string;
  log?: (message: string) => void;
}

export interface RunResult {
  plan: IssuePlan;
  body: string;
  rows: FailRow[];
  notChecked: NotChecked[];
}

export async function run(opts: RunOptions): Promise<RunResult> {
  const f = opts.fetchImpl ?? fetch;
  const log = opts.log ?? ((m: string) => console.log(m));
  const rows: FailRow[] = [];
  const notChecked: NotChecked[] = [];

  const repos = await listRepos(f, opts.apiUrl, opts.org, opts.token);
  for (const repo of repos) {
    const branch = repo.default_branch;
    try {
      const workflows = await listActiveWorkflows(
        f,
        opts.apiUrl,
        opts.org,
        repo.name,
        opts.token,
      );
      for (const wf of workflows) {
        const runs = await latestRuns(
          f,
          opts.apiUrl,
          opts.org,
          repo.name,
          wf.id,
          branch,
          opts.token,
        );
        const streak = summarizeStreak(runs);
        if (
          streak.failing &&
          streak.failingSince !== null &&
          streak.url !== null
        ) {
          rows.push({
            repo: repo.name,
            workflow: wf.name,
            failingSince: streak.failingSince,
            consecutive: streak.consecutive,
            bounded: streak.bounded,
            url: streak.url,
          });
        }
      }
    } catch (error) {
      const status = error instanceof ApiError ? error.status : 0;
      notChecked.push({ repo: repo.name, status });
      log(
        `not checked: ${repo.name} (${status === 0 ? String(error) : `HTTP ${status}`})`,
      );
    }
  }

  const body = renderBody({
    org: opts.org,
    rows,
    notChecked,
    now: opts.now ?? new Date(),
    by: opts.runUrl ?? 'local dry run',
  });

  const issue = await findHealthIssue(
    f,
    opts.apiUrl,
    opts.repository,
    opts.token,
  );
  const plan = planIssue(
    issue === null
      ? null
      : { number: issue.number, state: issue.state, body: issue.body },
    rows.length,
    body,
  );

  const summaryFile = opts.stepSummary ?? process.env.GITHUB_STEP_SUMMARY;
  if (summaryFile !== undefined && summaryFile !== '') {
    appendFileSync(summaryFile, body);
  }

  if (opts.dryRun) {
    log(`plan: ${plan.action}${'number' in plan ? ` #${plan.number}` : ''}`);
    log(body);
    return { plan, body, rows, notChecked };
  }

  switch (plan.action) {
    case 'create':
      await apiWrite(
        f,
        'POST',
        `${opts.apiUrl}/repos/${opts.repository}/issues`,
        {
          title: ISSUE_TITLE,
          body: plan.body,
        },
        opts.token,
      );
      log(`created "${ISSUE_TITLE}"`);
      break;
    case 'update':
      await apiWrite(
        f,
        'PATCH',
        `${opts.apiUrl}/repos/${opts.repository}/issues/${plan.number}`,
        {
          body: plan.body,
        },
        opts.token,
      );
      log(`updated "${ISSUE_TITLE}" #${plan.number}`);
      break;
    case 'reopen':
      await apiWrite(
        f,
        'PATCH',
        `${opts.apiUrl}/repos/${opts.repository}/issues/${plan.number}`,
        {
          body: plan.body,
          state: 'open',
        },
        opts.token,
      );
      log(`reopened "${ISSUE_TITLE}" #${plan.number}`);
      break;
    case 'close':
      await apiWrite(
        f,
        'PATCH',
        `${opts.apiUrl}/repos/${opts.repository}/issues/${plan.number}`,
        {
          body: plan.body,
          state: 'closed',
          state_reason: 'completed',
        },
        opts.token,
      );
      log(`closed "${ISSUE_TITLE}" #${plan.number}`);
      break;
    case 'none':
      log(`"${ISSUE_TITLE}" already up to date`);
      break;
  }
  return { plan, body, rows, notChecked };
}

if (import.meta.main) {
  const token = process.env.GITHUB_TOKEN;
  if (token === undefined || token === '') {
    console.error('org-health: GITHUB_TOKEN is required');
    process.exit(2);
  }
  try {
    await run({
      token,
      org: process.env.ORG ?? 'qntx',
      repository: process.env.REPOSITORY ?? 'qntx/workflows',
      apiUrl: process.env.GITHUB_API_URL ?? 'https://api.github.com',
      dryRun: process.env.DRY_RUN === 'true',
      runUrl: process.env.RUN_URL,
    });
  } catch (error) {
    console.error(
      `org-health: ${error instanceof Error ? error.message : String(error)}`,
    );
    process.exit(1);
  }
}
