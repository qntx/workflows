export interface FixtureExports {
  add: (a: number, b: number) => number;
}

export const instantiate = async (
  bytes: ArrayBuffer,
): Promise<FixtureExports> => {
  const { instance } = await WebAssembly.instantiate(bytes);
  return instance.exports as unknown as FixtureExports;
};
