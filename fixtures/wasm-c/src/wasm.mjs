export const instantiate = async (bytes) => {
  const { instance } = await WebAssembly.instantiate(bytes);
  return instance.exports;
};
