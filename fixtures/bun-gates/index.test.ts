import { expect, test } from 'bun:test';
import { fixture } from './index';

test('fixture module loads', () => {
  expect(fixture).toBe('bun-gates');
});
