import { expect, test } from 'bun:test';
import { instantiate } from './src/wasm.mjs';

test('wasm add', async () => {
  const bytes = await Bun.file('dist/fixture_wasm_c.wasm').arrayBuffer();
  const exports = await instantiate(bytes);
  expect(exports.add(20, 22)).toBe(42);
});
