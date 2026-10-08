import { expect, test } from 'bun:test';
import { inc } from './index';

test('inc adds one', () => {
  expect(inc(41)).toBe(42);
});
