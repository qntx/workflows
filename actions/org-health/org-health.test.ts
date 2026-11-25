import { describe, expect, test } from 'bun:test';
import {
  ISSUE_TITLE,
  MARKER,
  type ExistingIssue,
  type FetchLike,
  listRepos,
  planIssue,
  renderBody,
  run,
  summarizeStreak,
  type WorkflowRun,
} from './org-health';

function wr(over: Partial<WorkflowRun>): WorkflowRun {
  return {
    event: 'push',
    head_branch: 'main',
    conclusion: 'success',
    created_at: '2026-01-01T00:00:00Z',
    html_url: 'https://example/run/1',
    ...over,
  };
}

describe('summarizeStreak', () => {
  test('newest non-ignored failure starts the streak; success ends it', () => {
    const s = summarizeStreak([
      wr({
        conclusion: 'failure',
        created_at: '2026-01-03T00:00:00Z',
        html_url: 'https://example/newest',
      }),
      wr({ conclusion: 'cancelled' }),
      wr({ conclusion: 'failure', created_at: '2026-01-02T00:00:00Z' }),
      wr({ conclusion: 'success', created_at: '2026-01-01T00:00:00Z' }),
    ]);
    expect(s.failing).toBe(true);
    expect(s.consecutive).toBe(2);
    expect(s.bounded).toBe(false);
    expect(s.failingSince).toBe('2026-01-02T00:00:00Z');
    expect(s.url).toBe('https://example/newest');
  });

  test('ignored conclusions neither break nor count', () => {
    for (const c of [
      'cancelled',
      'skipped',
      'neutral',
      'stale',
      'action_required',
      null,
    ]) {
      const s = summarizeStreak([
        wr({ conclusion: 'failure', created_at: '2026-01-02T00:00:00Z' }),
        wr({ conclusion: c }),
        wr({ conclusion: 'success', created_at: '2026-01-01T00:00:00Z' }),
      ]);
      expect(s.failing).toBe(true);
      expect(s.consecutive).toBe(1);
    }
  });

  test('all failing conclusions count', () => {
    for (const c of ['failure', 'timed_out', 'startup_failure']) {
      const s = summarizeStreak([
        wr({ conclusion: c, created_at: '2026-01-02T00:00:00Z' }),
        wr({ conclusion: 'success', created_at: '2026-01-01T00:00:00Z' }),
      ]);
      expect(s.failing).toBe(true);
      expect(s.consecutive).toBe(1);
    }
  });

  test('no success in page marks the streak as a lower bound', () => {
    const s = summarizeStreak([
      wr({
        conclusion: 'failure',
        created_at: '2026-01-03T00:00:00Z',
        html_url: 'https://example/newest',
      }),
      wr({ conclusion: 'failure', created_at: '2026-01-02T00:00:00Z' }),
      wr({ conclusion: 'failure', created_at: '2026-01-01T00:00:00Z' }),
    ]);
    expect(s.failing).toBe(true);
    expect(s.consecutive).toBe(3);
    expect(s.bounded).toBe(true);
    expect(s.failingSince).toBe('2026-01-01T00:00:00Z');
  });

  test('newest success means not failing', () => {
    const s = summarizeStreak([
      wr({ conclusion: 'success' }),
      wr({ conclusion: 'failure' }),
    ]);
    expect(s.failing).toBe(false);
    expect(s.consecutive).toBe(0);
  });

  test('empty or all-ignored runs are not failing', () => {
    expect(summarizeStreak([]).failing).toBe(false);
    expect(summarizeStreak([wr({ conclusion: 'cancelled' })]).failing).toBe(
      false,
    );
  });
});

describe('latestRuns filtering (via fake fetch)', () => {
  test('push/schedule on the default branch only', async () => {
    const { latestRuns } = await import('./org-health');
    const f: FetchLike = async (input) =>
      new Response(
        JSON.stringify({
          workflow_runs: [
            wr({ event: 'pull_request', conclusion: 'failure' }),
            wr({ event: 'workflow_dispatch', conclusion: 'failure' }),
            wr({ event: 'dynamic', conclusion: 'failure' }),
            wr({ event: 'push', head_branch: 'other', conclusion: 'failure' }),
            wr({
              event: 'schedule',
              conclusion: 'failure',
              created_at: '2026-01-02T00:00:00Z',
            }),
            wr({
              event: 'push',
              conclusion: 'success',
              created_at: '2026-01-01T00:00:00Z',
            }),
          ],
        }),
        { status: 200 },
      );
    const runs = await latestRuns(
      f,
      'https://api.test',
      'o',
      'r',
      7,
      'main',
      'tok',
    );
    expect(runs).toHaveLength(2);
    expect(runs.map((r) => r.event)).toEqual(['schedule', 'push']);
    const s = summarizeStreak(runs);
    expect(s.failing).toBe(true);
    expect(s.consecutive).toBe(1);
  });
});

describe('listRepos', () => {
  test('drops archived and private, keeps forks, sorts by name, paginates', async () => {
    const seen: string[] = [];
    const f: FetchLike = async (input) => {
      const url = String(input);
      seen.push(url);
      if (!url.includes('page=2')) {
        return new Response(
          JSON.stringify([
            {
              name: 'zeta',
              default_branch: 'main',
              archived: false,
              private: false,
            },
            {
              name: 'archived-repo',
              default_branch: 'main',
              archived: true,
              private: false,
            },
            {
              name: 'alpha',
              default_branch: 'main',
              archived: false,
              private: false,
            },
          ]),
          {
            status: 200,
            headers: { link: '<https://api.test/next?page=2>; rel="next"' },
          },
        );
      }
      return new Response(
        JSON.stringify([
          {
            name: 'priv',
            default_branch: 'main',
            archived: false,
            private: true,
          },
          {
            name: 'mid',
            default_branch: 'main',
            archived: false,
            private: false,
          },
        ]),
        { status: 200 },
      );
    };
    const repos = await listRepos(f, 'https://api.test', 'qntx', 'tok');
    expect(seen).toHaveLength(2);
    expect(repos.map((r) => r.name)).toEqual(['alpha', 'mid', 'zeta']);
  });
});

describe('renderBody', () => {
  test('golden body with rows, bounds, and not-checked', () => {
    const body = renderBody({
      org: 'qntx',
      rows: [
        {
          repo: 'corx',
          workflow: 'CI',
          failingSince: '2026-10-01T12:00:00Z',
          consecutive: 12,
          bounded: false,
          url: 'https://example/corx/1',
        },
        {
          repo: 'sh',
          workflow: 'Sync',
          failingSince: '2026-09-15T00:00:00Z',
          consecutive: 30,
          bounded: true,
          url: 'https://example/sh/9',
        },
      ],
      notChecked: [{ repo: 'priv', status: 403 }],
      now: new Date('2026-11-01T05:23:00.000Z'),
      by: 'https://github.com/qntx/workflows/actions/runs/123',
    });
    expect(body).toBe(
      `${MARKER}

Public, non-archived repositories of \`qntx\`; the latest completed \`push\`/\`schedule\` run of each active workflow on the default branch, unless a newer tag run succeeded.

Private repositories are out of scope: their Actions are currently blocked by billing.

| Repository | Workflow | Failing since | Consecutive failures | Latest failing run |
| --- | --- | --- | --- | --- |
| corx | CI | 2026-10-01 | 12 | [run](https://example/corx/1) |
| sh | Sync | ≤2026-09-15 | ≥30 | [run](https://example/sh/9) |

Not checked:

- priv (HTTP 403)

Updated 2026-11-01T05:23:00.000Z by https://github.com/qntx/workflows/actions/runs/123
`,
    );
  });

  test('empty table renders "No failing workflows."', () => {
    const body = renderBody({
      org: 'qntx',
      rows: [],
      notChecked: [],
      now: new Date('2026-11-01T05:23:00.000Z'),
      by: 'local dry run',
    });
    expect(body).toContain('No failing workflows.');
    expect(body).not.toContain('| Repository |');
    expect(body).not.toContain('Not checked:');
    expect(body).toContain('Updated 2026-11-01T05:23:00.000Z by local dry run');
  });
});

describe('planIssue', () => {
  const open = (body: string): ExistingIssue => ({
    number: 5,
    state: 'open',
    body,
  });
  const closed = (body: string): ExistingIssue => ({
    number: 5,
    state: 'closed',
    body,
  });

  test('no issue + failures -> create', () => {
    expect(planIssue(null, 2, 'B')).toEqual({ action: 'create', body: 'B' });
  });

  test('no issue + no failures -> none', () => {
    expect(planIssue(null, 0, 'B')).toEqual({ action: 'none' });
  });

  test('closed issue + failures -> reopen with new body', () => {
    expect(planIssue(closed('old'), 1, 'B')).toEqual({
      action: 'reopen',
      number: 5,
      body: 'B',
    });
  });

  test('open issue + changed body -> update', () => {
    expect(planIssue(open('old body'), 1, 'B')).toEqual({
      action: 'update',
      number: 5,
      body: 'B',
    });
  });

  test('open issue + same body modulo Updated line -> none', () => {
    const existing = open('header\nUpdated 2026-11-01T00:00:00.000Z by x\n');
    expect(
      planIssue(existing, 3, 'header\nUpdated 2026-11-02T00:00:00.000Z by y\n'),
    ).toEqual({
      action: 'none',
    });
  });

  test('open issue + no failures -> close', () => {
    expect(planIssue(open('x'), 0, 'B')).toEqual({
      action: 'close',
      number: 5,
      body: 'B',
    });
  });

  test('closed issue + no failures -> none', () => {
    expect(planIssue(closed('x'), 0, 'B')).toEqual({ action: 'none' });
  });
});

function jsonResponse(
  body: unknown,
  status = 200,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), { status, headers });
}

interface Call {
  method: string;
  url: string;
  body?: unknown;
}

function fakeFetch(
  routes: Record<string, { status?: number; body?: unknown }>,
  calls: Call[],
): FetchLike {
  return async (input, init) => {
    const url = String(input);
    calls.push({
      method: init?.method ?? 'GET',
      url,
      body:
        init?.body !== undefined ? JSON.parse(String(init.body)) : undefined,
    });
    for (const [prefix, route] of Object.entries(routes)) {
      if (url.startsWith(prefix)) {
        return jsonResponse(route.body ?? {}, route.status ?? 200);
      }
    }
    return jsonResponse({ message: 'unrouted' }, 500);
  };
}

const RUNS_FAILING = {
  workflow_runs: [
    wr({
      conclusion: 'failure',
      created_at: '2026-01-03T00:00:00Z',
      html_url: 'https://example/r/3',
    }),
    wr({
      conclusion: 'failure',
      created_at: '2026-01-02T00:00:00Z',
      html_url: 'https://example/r/2',
    }),
    wr({
      conclusion: 'success',
      created_at: '2026-01-01T00:00:00Z',
      html_url: 'https://example/r/1',
    }),
  ],
};

function orgRoutes(): Record<string, { status?: number; body?: unknown }> {
  return {
    'https://api.test/orgs/qntx/repos': {
      body: [
        {
          name: 'corx',
          default_branch: 'main',
          archived: false,
          private: false,
        },
        {
          name: 'broken',
          default_branch: 'main',
          archived: false,
          private: false,
        },
        {
          name: 'archived',
          default_branch: 'main',
          archived: true,
          private: false,
        },
      ],
    },
    'https://api.test/repos/qntx/corx/actions/workflows?per_page=100': {
      body: {
        workflows: [
          { id: 11, name: 'CI', state: 'active' },
          { id: 12, name: 'Disabled', state: 'disabled_manually' },
        ],
      },
    },
    'https://api.test/repos/qntx/corx/actions/workflows/11/runs': {
      body: RUNS_FAILING,
    },
    'https://api.test/repos/qntx/broken/actions/workflows': {
      status: 404,
      body: { message: 'Not Found' },
    },
    'https://api.test/repos/qntx/workflows/issues': { body: [] },
  };
}

describe('run()', () => {
  const base = {
    token: 'tok',
    org: 'qntx',
    repository: 'qntx/workflows',
    apiUrl: 'https://api.test',
    now: new Date('2026-02-01T00:00:00.000Z'),
    stepSummary: '',
    log: () => {},
  };

  test('dry run performs only GET requests and plans a create', async () => {
    const calls: Call[] = [];
    const res = await run({
      ...base,
      dryRun: true,
      fetchImpl: fakeFetch(orgRoutes(), calls),
    });
    expect(calls.every((c) => c.method === 'GET')).toBe(true);
    expect(res.plan.action).toBe('create');
    expect(res.rows).toEqual([
      {
        repo: 'corx',
        workflow: 'CI',
        failingSince: '2026-01-02T00:00:00Z',
        consecutive: 2,
        bounded: false,
        url: 'https://example/r/3',
      },
    ]);
    expect(res.notChecked).toEqual([{ repo: 'broken', status: 404 }]);
    expect(res.body).toContain(
      '| corx | CI | 2026-01-02 | 2 | [run](https://example/r/3) |',
    );
  });

  test('a newer successful tag run clears a default-branch failure', async () => {
    const tagRun = (head_branch: string) => ({
      workflow_runs: [
        wr({ head_branch, created_at: '2026-01-04T00:00:00Z' }),
        wr({ head_branch: 'v0.0.1', created_at: '2026-01-02T12:00:00Z' }),
      ],
    });
    const routesFor = (head_branch: string) => ({
      'https://api.test/repos/qntx/corx/actions/workflows/11/runs?event=push&status=success':
        { body: tagRun(head_branch) },
      'https://api.test/repos/qntx/corx/git/ref/tags/v1.0.0': {
        body: { ref: 'refs/tags/v1.0.0' },
      },
      'https://api.test/repos/qntx/corx/git/ref/tags/': {
        status: 404,
        body: { message: 'Not Found' },
      },
      ...orgRoutes(),
    });
    const cleared = await run({
      ...base,
      dryRun: true,
      fetchImpl: fakeFetch(routesFor('v1.0.0'), []),
    });
    expect(cleared.rows).toEqual([]);
    expect(cleared.notChecked).toEqual([{ repo: 'broken', status: 404 }]);

    // A newer success on a non-tag ref, or an older tag success, clears nothing.
    const calls: Call[] = [];
    const kept = await run({
      ...base,
      dryRun: true,
      fetchImpl: fakeFetch(routesFor('feature'), calls),
    });
    expect(kept.rows).toHaveLength(1);
    expect(
      calls.filter((c) => c.url.includes('/git/ref/tags/')).map((c) => c.url),
    ).toEqual(['https://api.test/repos/qntx/corx/git/ref/tags/feature']);
  });

  test('write mode creates the issue when none exists', async () => {
    const calls: Call[] = [];
    const res = await run({
      ...base,
      dryRun: false,
      fetchImpl: fakeFetch(orgRoutes(), calls),
    });
    const posts = calls.filter((c) => c.method === 'POST');
    expect(posts).toEqual([
      {
        method: 'POST',
        url: 'https://api.test/repos/qntx/workflows/issues',
        body: { title: ISSUE_TITLE, body: res.body },
      },
    ]);
    expect(calls.filter((c) => c.method === 'PATCH')).toEqual([]);
  });

  test('write mode patches the existing open issue', async () => {
    const calls: Call[] = [];
    const routes = orgRoutes();
    routes['https://api.test/repos/qntx/workflows/issues'] = {
      body: [{ number: 42, title: ISSUE_TITLE, state: 'open', body: 'stale' }],
    };
    const res = await run({
      ...base,
      dryRun: false,
      fetchImpl: fakeFetch(routes, calls),
    });
    expect(calls.filter((c) => c.method === 'POST')).toEqual([]);
    expect(calls.filter((c) => c.method === 'PATCH')).toEqual([
      {
        method: 'PATCH',
        url: 'https://api.test/repos/qntx/workflows/issues/42',
        body: { body: res.body },
      },
    ]);
  });

  test('write mode closes the issue when nothing fails', async () => {
    const calls: Call[] = [];
    const routes = orgRoutes();
    routes['https://api.test/repos/qntx/corx/actions/workflows/11/runs'] = {
      body: { workflow_runs: [wr({ conclusion: 'success' })] },
    };
    routes['https://api.test/repos/qntx/workflows/issues'] = {
      body: [{ number: 42, title: ISSUE_TITLE, state: 'open', body: 'stale' }],
    };
    const res = await run({
      ...base,
      dryRun: false,
      fetchImpl: fakeFetch(routes, calls),
    });
    expect(res.plan.action).toBe('close');
    expect(calls.filter((c) => c.method === 'PATCH')).toEqual([
      {
        method: 'PATCH',
        url: 'https://api.test/repos/qntx/workflows/issues/42',
        body: { body: res.body, state: 'closed', state_reason: 'completed' },
      },
    ]);
  });

  test('a user-owned issue is found via the body marker fallback', async () => {
    const calls: Call[] = [];
    const routes = orgRoutes();
    const f = async (
      input: string | URL,
      init?: RequestInit,
    ): Promise<Response> => {
      const url = String(input);
      calls.push({ method: init?.method ?? 'GET', url, body: undefined });
      if (url.includes('creator=')) {
        return jsonResponse([]); // bot filter finds nothing
      }
      if (url.startsWith('https://api.test/repos/qntx/workflows/issues')) {
        return jsonResponse([
          {
            number: 9,
            title: ISSUE_TITLE,
            state: 'open',
            body: `x\n${MARKER}\ny`,
          },
          { number: 10, title: ISSUE_TITLE, state: 'open', body: 'no marker' },
        ]);
      }
      for (const [prefix, route] of Object.entries(routes)) {
        if (url.startsWith(prefix))
          return jsonResponse(route.body ?? {}, route.status ?? 200);
      }
      return jsonResponse({}, 500);
    };
    const res = await run({ ...base, dryRun: false, fetchImpl: f });
    expect(res.plan).toEqual({ action: 'update', number: 9, body: res.body });
  });
});
