/**
 * Auto-generates the keymaps table in README.md from lua/telegram/config.lua
 *
 * Usage: npx tsx scripts/gen-keymaps.ts
 *
 * Reads M.default_keys and M.key_labels from config.lua,
 * builds a markdown table, and replaces the section
 * between <!-- KEYMAPS_TABLE_START --> and <!-- KEYMAPS_TABLE_END -->
 * in README.md.
 */

import { readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';

const ROOT = join(dirname(__filename), '..');
const CONFIG_LUA = join(ROOT, 'lua', 'telegram', 'config.lua');
const README_MD = join(ROOT, 'README.md');

type KeyMap = Record<string, string>;

/**
 * Parse a Lua table like:
 *   M.foo = {
 *       key = "value",
 *       key2 = "value2",
 *   }
 */
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

// Parse config.lua
const configLua = readFileSync(CONFIG_LUA, 'utf-8');
const defaults = parseLuaTable(configLua, 'default_keys');
const labels = parseLuaTable(configLua, 'key_labels');

// Preserve insertion order from default_keys
const keys = Object.keys(defaults);
const table = generateTable(keys, labels, defaults);

// Read and update README.md
let readme = readFileSync(README_MD, 'utf-8');

const startIdx = readme.indexOf(START_MARKER);
const endIdx = readme.indexOf(END_MARKER);

if (startIdx === -1 || endIdx === -1) {
  console.error('❌ Could not find markers in README.md');
  console.error(`  ${START_MARKER}: ${startIdx === -1 ? 'not found' : 'ok'}`);
  console.error(`  ${END_MARKER}: ${endIdx === -1 ? 'not found' : 'ok'}`);
  process.exit(1);
}

const before = readme.slice(0, startIdx + START_MARKER.length);
const after = readme.slice(endIdx);
readme = before + '\n' + table + '\n' + after;

writeFileSync(README_MD, readme);
console.log('✅ Keymaps table updated in README.md');
console.log(`   ${keys.length} keys generated`);
