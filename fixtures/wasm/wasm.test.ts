import { expect, test } from 'bun:test';
import { instantiate } from './src/wasm';

test('wasm add', async () => {
  const bytes = await Bun.file('dist/fixture_wasm.wasm').arrayBuffer();
  const exports = await instantiate(bytes);
  expect(exports.add(20, 22)).toBe(42);
});
