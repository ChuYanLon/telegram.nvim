import path from 'path';
import fs from 'fs';
import { execSync } from 'child_process';

const TG_TDLIB_PATH = process.env.TG_TDLIB_PATH;

export function detectTdlibPath(): string | undefined {
  if (TG_TDLIB_PATH) {
    if (fs.existsSync(TG_TDLIB_PATH)) return TG_TDLIB_PATH;
    console.warn(`TG_TDLIB_PATH set but not found: ${TG_TDLIB_PATH}`);
  }

  const isWin = process.platform === 'win32';
  const isMac = process.platform === 'darwin';
  const isLinux = process.platform === 'linux';

  if (isLinux) {
    try {
      const out = execSync('ldconfig -p 2>/dev/null | grep -i libtdjson', { encoding: 'utf8' });
      for (const line of out.trim().split('\n')) {
        const m = line.match(/=>\s*(\S+libtdjson\S+)/);
        if (m && fs.existsSync(m[1])) return m[1];
      }
    } catch { /* ignore */ }
  }

  if (isMac) {
    try {
      const out = execSync('mdfind -name libtdjson 2>/dev/null', { encoding: 'utf8' });
      for (const f of out.trim().split('\n')) {
        if (f && (f.endsWith('.dylib') || f.endsWith('.so')) && fs.existsSync(f)) return f;
      }
    } catch { /* ignore */ }
  }

  if (isWin) {
    try {
      const out = execSync('where tdjson.dll 2>nul', { encoding: 'utf8' });
      for (const f of out.trim().split('\n')) {
        if (f && fs.existsSync(f)) return f;
      }
    } catch { /* ignore */ }
  }

  const home = process.env.HOME || process.env.USERPROFILE || '';
  const localAppData = process.env.LOCALAPPDATA || '';
  const programFiles = process.env.PROGRAMFILES || 'C:\\Program Files';

  const candidates = isLinux
    ? [
        `/usr/lib/${process.arch === 'x64' ? 'x86_64-linux-gnu' : process.arch === 'arm64' ? 'aarch64-linux-gnu' : ''}/libtdjson.so`,
        `/usr/local/lib/${process.arch === 'x64' ? 'x86_64-linux-gnu' : process.arch === 'arm64' ? 'aarch64-linux-gnu' : ''}/libtdjson.so`,
        `${home}/.local/lib/${process.arch === 'x64' ? 'x86_64-linux-gnu' : process.arch === 'arm64' ? 'aarch64-linux-gnu' : ''}/libtdjson.so`,
        '/usr/lib/libtdjson.so',
        '/usr/local/lib/libtdjson.so',
        `${home}/.local/lib/libtdjson.so`,
        '/usr/lib64/libtdjson.so',
        '/opt/lib/libtdjson.so',
      ]
    : isMac
    ? [
        '/opt/homebrew/lib/libtdjson.dylib',
        '/usr/local/lib/libtdjson.dylib',
        `${home}/.local/lib/libtdjson.dylib`,
        '/usr/lib/libtdjson.dylib',
      ]
    : [
        `${localAppData}\\tdlib\\bin\\tdjson.dll`,
        `${programFiles}\\tdlib\\bin\\tdjson.dll`,
        `${programFiles} (x86)\\tdlib\\bin\\tdjson.dll`,
        `${home}\\tdlib\\bin\\tdjson.dll`,
      ];

  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }

  if (isLinux) {
    try {
      const ldpath = process.env.LD_LIBRARY_PATH || '';
      for (const dir of ldpath.split(':')) {
        const p = path.join(dir, 'libtdjson.so');
        if (fs.existsSync(p)) return p;
      }
    } catch { /* ignore */ }
    try {
      const out = execSync('find /usr/lib /usr/local/lib /opt/lib /home -name "libtdjson.so*" -type f,l 2>/dev/null | head -3', { encoding: 'utf8' });
      for (const f of out.trim().split('\n')) {
        if (f && fs.existsSync(f)) return f;
      }
    } catch { /* ignore */ }
  }

  return undefined;
}

const resolvedTdlibPath = detectTdlibPath();

export function getResolvedTdlibPath(): string | undefined {
  return resolvedTdlibPath;
}

export function initTdlibModule(): void {
  if (resolvedTdlibPath) {
    console.log(`TDLib library: ${resolvedTdlibPath}`);
  } else {
    const msg = 'Cannot find libtdjson. Install TDLib or set TG_TDLIB_PATH env var.';
    if (!TG_TDLIB_PATH) {
      console.error(msg);
      process.exit(1);
    }
    console.log('TDLib library: auto');
  }
}
