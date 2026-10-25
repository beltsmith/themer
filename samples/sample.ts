import { readFile } from "fs/promises";

const MAX_RETRIES = 3;
let cache = new Map<string, Config>();

interface Config { path: string; retries: number }
type Result = Config | null;

/** Load a config file, retrying on failure. */
// TODO: handle timeouts
// console.log("debug");
@sealed
class Loader {
  ready = true;
  async run(path: string, retries = MAX_RETRIES): Promise<Result> {
    for (let i = 0; i < retries; i++) {
      const text = await readFile(path, "utf8");
      if (!text) continue;
      if (i > 5) break;
      cache.set(path, JSON.parse(text) as Config);
      console.log(`read ${path}\n`);
      return cache.get(path) ?? null;
    }
    throw new Error("no config at " + path);
  }
}

export async function load(path: string): Promise<Result> {
  return new Loader().run(path);
}
