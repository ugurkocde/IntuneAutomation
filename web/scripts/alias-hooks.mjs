// Module resolution hook that maps the project's "~/..." path alias to web/src
// so plain `node --experimental-strip-types` can import TS modules that use it.
// Used by scripts/export-generator-instructions.mjs.
const SRC = new URL("../src/", import.meta.url).href;

export async function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith("~/")) {
    let target = SRC + specifier.slice(2);
    if (!/\.(ts|tsx|js|mjs|cjs|json)$/.test(specifier)) target += ".ts";
    return nextResolve(target, context);
  }
  return nextResolve(specifier, context);
}
