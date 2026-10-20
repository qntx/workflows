import { expect, test } from 'bun:test';

import { prebuilt } from './dist/bundle.js';

// The dist/ tree is supplied by the `artifact` input's download step; the files
// check and this test both prove it landed relative to the package directory.
test('fixture sees the downloaded artifact', () => {
  expect(prebuilt).toBe(true);
  expect(process.env.FIXTURE_TEST_SCRIPT).toBe('1');
});
