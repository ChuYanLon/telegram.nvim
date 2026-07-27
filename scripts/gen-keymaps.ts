/**
 * Auto-generates the keymaps table in README.md and wiki files
 * from lua/telegram/config.lua
 *
 * Usage: npx tsx scripts/gen-keymaps.ts
 *
 * Reads M.default_keys and M.key_labels from config.lua,
 * builds a markdown table, and replaces the section
 * between <!-- KEYMAPS_TABLE_START --> and <!-- KEYMAPS_TABLE_END -->
 * in all target markdown files.
 */

import { readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';

const ROOT = join(dirname(__filename), '..');
const CONFIG_LUA = join(ROOT, 'lua', 'telegram', 'config.lua');
const TARGETS = [
  join(ROOT, 'README.md'),
  join(ROOT, 'wiki', 'Keymaps.md'),
  join(ROOT, 'wiki', 'Configuration.md'),
];

type KeyMap = Record<string, string>;

/** Parse a Lua table like: M.foo = { key = "value", ... } */
function parseLuaTable(text: string, tableName: string): KeyMap {
  const result: KeyMap = {};
  const tableRegex = new RegExp(
    `M\\.${tableName}\\s*=\\s*\\{([^}]+)\\}`,
    'm'
  );
  const match = text.match(tableRegex);
  if (!match) return result;

  const body = match[1];
  const entryRegex = /^\s+(\w+)\s*=\s*"([^"]*)"/gm;
  let m: RegExpExecArray | null;
  while ((m = entryRegex.exec(body)) !== null) {
    result[m[1]] = m[2];
  }
  return result;
}

function generateTable(keys: string[], labels: KeyMap, defaults: KeyMap): string {
  const header = '| Key name | Default | Action |\n' +
    '|----------|---------|--------|\n';
  const rows = keys.map(k => {
    const label = labels[k] ?? k;
    return `| \`${k}\` | \`${defaults[k]}\` | ${label} |`;
  });
  return header + rows.join('\n') + '\n';
}

const START_MARKER = '<!-- KEYMAPS_TABLE_START -->';
const END_MARKER = '<!-- KEYMAPS_TABLE_END -->';

const configLua = readFileSync(CONFIG_LUA, 'utf-8');
const defaults = parseLuaTable(configLua, 'default_keys');
const labels = parseLuaTable(configLua, 'key_labels');
const keys = Object.keys(defaults);
const table = generateTable(keys, labels, defaults);

let updated = 0;
let skipped = 0;

for (const filePath of TARGETS) {
  let content: string;
  try {
    content = readFileSync(filePath, 'utf-8');
  } catch {
    console.log(`  ⚠ ${filePath.replace(ROOT, '.')} — not found, skipping`);
    skipped++;
    continue;
  }

  const startIdx = content.indexOf(START_MARKER);
  const endIdx = content.indexOf(END_MARKER);

  if (startIdx === -1 || endIdx === -1) {
    console.log(`  ⚠ ${filePath.replace(ROOT, '.')} — no markers found, skipping`);
    skipped++;
    continue;
  }

  const before = content.slice(0, startIdx + START_MARKER.length);
  const after = content.slice(endIdx);
  content = before + '\n' + table + '\n' + after;

  writeFileSync(filePath, content);
  console.log(`  ✅ ${filePath.replace(ROOT, '.')}`);
  updated++;
}

console.log(`\nDone: ${updated} updated, ${skipped} skipped, ${keys.length} keys`);
