import { expect, test } from 'bun:test';

import { fixture } from './index.js';

// Only the declared test script sets the env marker; a raw `bun test`
// fallback would find this file but run it without the variable.
test('fixture exports through the declared test script', () => {
  expect(fixture).toBe(true);
  expect(process.env.FIXTURE_TEST_SCRIPT).toBe('1');
});
