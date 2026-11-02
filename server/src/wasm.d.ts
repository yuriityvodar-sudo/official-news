/** A WebAssembly module, as Wrangler bundles a .wasm import (#230: the stories' grouping, src/stories/group.wasm). */
declare module "*.wasm" {
  const module: WebAssembly.Module;
  export default module;
}
