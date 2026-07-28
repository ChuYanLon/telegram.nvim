/**
 * Auto-generates the keymaps table in README.md and wiki files
 * from lua/telegram/config.lua, and the tools table from
 * lua/telegram/tools.lua.
 *
 * Usage: npx tsx scripts/gen-keymaps.ts
 *
 * Keymaps: parses M.default_keys and M.key_labels from config.lua,
 * builds a markdown table between <!-- KEYMAPS_TABLE_START/END -->
 * Tools: parses M.register(...) calls from tools.lua,
 * builds a markdown table between <!-- TOOLS_TABLE_START/END -->
 */

import { readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';

const ROOT = join(dirname(__filename), '..');
const CONFIG_LUA = join(ROOT, 'lua', 'telegram', 'config.lua');
const TOOLS_LUA = join(ROOT, 'lua', 'telegram', 'tools.lua');
const TARGETS = [
  join(ROOT, 'README.md'),
  join(ROOT, 'wiki', 'Home.md'),
  join(ROOT, 'wiki', 'Keymaps.md'),
  join(ROOT, 'wiki', 'Configuration.md'),
  join(ROOT, 'wiki', 'Installation.md'),
];

// ── Keymaps ────────────────────────────────────────────────────────────

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

function generateKeymapTable(keys: string[], labels: KeyMap, defaults: KeyMap): string {
  const header = '| Key name | Default | Action |\n' +
    '|----------|---------|--------|\n';
  const rows = keys.map(k => {
    const label = labels[k] ?? k;
    return `| \`${k}\` | \`${defaults[k]}\` | ${label} |`;
  });
  return header + rows.join('\n') + '\n';
}

// ── Tools ──────────────────────────────────────────────────────────────

interface Tool {
  name: string;
  description: string;
}

/** Parse M.register("name", { description = "...", ... }) calls from tools.lua */
function parseTools(text: string): Tool[] {
  const tools: Tool[] = [];
  // Match: M.register("name", { ... description = "..." ... })
  const regex = /M\.register\("(\w+)"[\s\S]*?description\s*=\s*"([^"]*)"/g;
  let m: RegExpExecArray | null;
  while ((m = regex.exec(text)) !== null) {
    tools.push({ name: m[1], description: m[2] });
  }
  return tools;
}

function generateToolTable(tools: Tool[]): string {
  const header = '| Tool | Description |\n' +
    '|------|-------------|\n';
  const rows = tools.map(t => {
    return `| \`@${t.name}\` | ${t.description} |`;
  });
  return header + rows.join('\n') + '\n';
}

// ── Replacer ───────────────────────────────────────────────────────────

function replaceBetween(content: string, startMarker: string, endMarker: string, table: string): string | null {
  const startIdx = content.indexOf(startMarker);
  const endIdx = content.indexOf(endMarker);

  if (startIdx === -1 || endIdx === -1) return null;

  const before = content.slice(0, startIdx + startMarker.length);
  const after = content.slice(endIdx);
  return before + '\n' + table + '\n' + after;
}

// ── Main ───────────────────────────────────────────────────────────────

const configLua = readFileSync(CONFIG_LUA, 'utf-8');
const defaults = parseLuaTable(configLua, 'default_keys');
const labels = parseLuaTable(configLua, 'key_labels');
const keymapTable = generateKeymapTable(Object.keys(defaults), labels, defaults);

const toolsLua = readFileSync(TOOLS_LUA, 'utf-8');
const tools = parseTools(toolsLua).sort((a, b) => a.name.localeCompare(b.name));
const toolTable = generateToolTable(tools);

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

  // Keymaps (optional — some files only have tools table)
  let working = content;
  const foundKeys = replaceBetween(working, '<!-- KEYMAPS_TABLE_START -->', '<!-- KEYMAPS_TABLE_END -->', keymapTable);
  if (foundKeys) working = foundKeys;

  // Tools (optional — some files only have keymaps)
  const foundTools = replaceBetween(working, '<!-- TOOLS_TABLE_START -->', '<!-- TOOLS_TABLE_END -->', toolTable);
  if (foundTools) working = foundTools;

  if (!foundKeys && !foundTools) {
    console.log(`  ⚠ ${filePath.replace(ROOT, '.')} — no markers found, skipping`);
    skipped++;
    continue;
  }

  if (working !== content) {
    writeFileSync(filePath, working);
    updated++;
    console.log(`  ✅ ${filePath.replace(ROOT, '.')}`);
  }
}

// ── Sync sections from README.md → wiki files ─────────────────────

const readmePath = join(ROOT, 'README.md');
interface SectionSync { marker: string; source: string; target: string; label: string; }
const sections: SectionSync[] = [
  { marker: 'FEATURES',     source: readmePath, target: join(ROOT, 'wiki', 'Home.md'),           label: 'features' },
  { marker: 'INSTALLATION', source: readmePath, target: join(ROOT, 'wiki', 'Installation.md'),   label: 'installation' },
  { marker: 'COMMANDS',     source: readmePath, target: join(ROOT, 'wiki', 'Keymaps.md'),        label: 'commands' },
  { marker: 'LUA_API',      source: readmePath, target: join(ROOT, 'wiki', 'Configuration.md'),  label: 'lua_api' },
  { marker: 'INPUT_EDITOR', source: readmePath, target: join(ROOT, 'wiki', 'Keymaps.md'),        label: 'input_editor' },
  { marker: 'MOUSE',        source: readmePath, target: join(ROOT, 'wiki', 'Keymaps.md'),        label: 'mouse' },
  { marker: 'DATABASE',     source: readmePath, target: join(ROOT, 'wiki', 'Configuration.md'),  label: 'database' },
  { marker: 'CONFIG_REFERENCE', source: readmePath, target: join(ROOT, 'wiki', 'Configuration.md'),  label: 'config_reference' },
];

for (const { marker, source, target, label } of sections) {
  try {
    const srcContent = readFileSync(source, 'utf-8');
    const start = srcContent.indexOf(`<!-- ${marker}_START -->`);
    const end = srcContent.indexOf(`<!-- ${marker}_END -->`);
    if (start === -1 || end === -1 || end <= start) continue;

    const sectionContent = srcContent.slice(
      start + `<!-- ${marker}_START -->`.length,
      end,
    ).trim();

    const tgtContent = readFileSync(target, 'utf-8');
    const result = replaceBetween(
      tgtContent,
      `<!-- ${marker}_START -->`,
      `<!-- ${marker}_END -->`,
      sectionContent,
    );

    if (result && result !== tgtContent) {
      writeFileSync(target, result);
      console.log(`  ✅ ${target.replace(ROOT, '.')} — ${label} synced`);
      updated++;
    }
  } catch (e) {
    console.log(`  ⚠ ${label} sync failed: ${(e as Error).message}`);
  }
}

console.log(`\nDone: ${updated} updated, ${skipped} skipped, ${Object.keys(defaults).length} keys, ${tools.length} tools`);
