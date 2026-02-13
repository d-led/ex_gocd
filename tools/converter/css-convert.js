#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const glob = require('glob');
const mkdirp = require('mkdirp');
const sass = require('sass');
const postcss = require('postcss');
const autoprefixer = require('autoprefixer');

function copyRecursiveSync(src, dest) {
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
    const names = fs.readdirSync(src);
    for (const name of names) {
      copyRecursiveSync(path.join(src, name), path.join(dest, name));
    }
  } else {
    fs.copyFileSync(src, dest);
  }
}

// In entry-point mode we only produce these basenames; remove them before writing so the run is idempotent
// and stale files are dropped when an entry is removed. Update this when adding/removing entries.
const ENTRY_POINT_OUTPUT_BASENAMES = ['new_dashboard.css', 'agents.css'];

function usage() {
  console.log('Usage: node css-convert.js <input_dir> <output_dir> [entry1 [entry2 ...]]');
  console.log('  If entries are given (paths relative to input_dir), only those are compiled.');
  console.log('  Idempotent: safe to run on each GoCD update; removes known outputs before writing.');
  console.log('  Example: node css-convert.js ../../gocd/.../new_stylesheets ../assets/css/gocd single_page_apps/new_dashboard.scss single_page_apps/agents.scss');
  console.log('  Without entries: globs all .scss except frameworks.scss (and files that import Rails-only deps).');
  process.exit(1);
}

function removeKnownOutputs(dir) {
  ENTRY_POINT_OUTPUT_BASENAMES.forEach((name) => {
    const p = path.join(dir, name);
    if (fs.existsSync(p)) {
      fs.unlinkSync(p);
      console.log('Removed (for idempotent run): ' + p);
    }
  });
}

const args = process.argv.slice(2);
if (args.length < 2) usage();
const inputDir = path.resolve(args[0]);
const outputDir = path.resolve(args[1]);
const entryRelPaths = args.slice(2);

if (!fs.existsSync(inputDir)) {
  console.error(`Input directory does not exist: ${inputDir}`);
  process.exit(2);
}

const converterDir = __dirname;
const stubsDir = path.join(converterDir, 'stubs');
const nodeModules = path.join(converterDir, 'node_modules');
const foundationPath = path.join(nodeModules, 'foundation-sites/scss');
const bourbonPath = path.join(nodeModules, 'bourbon');

function buildLoadPaths(baseDir) {
  const base = baseDir || inputDir;
  return [
    base,
    path.join(base, 'shared'),
    nodeModules,
    bourbonPath,
    foundationPath,
    path.join(foundationPath, 'util'),
  ].filter(p => fs.existsSync(p));
}

async function processOne(entryPath, outPath, loadBaseDir) {
  const loadPaths = buildLoadPaths(loadBaseDir);
  const result = sass.compile(entryPath, { style: 'expanded', loadPaths });
  let css = result.css;
  const post = await postcss([autoprefixer]).process(css, { from: undefined });
  css = post.css;
  const header = `/* Converted from: ${path.relative(inputDir, entryPath)} */\n`;
  const outDir = path.dirname(outPath);
  mkdirp.sync(outDir);
  fs.writeFileSync(outPath, header + css, 'utf8');
  console.log(`Wrote ${outPath}`);
}

function entryPointMode() {
  const entries = entryRelPaths.map(rel => path.join(inputDir, rel));
  const missing = entries.filter(p => !fs.existsSync(p));
  if (missing.length) {
    console.error('Entry file(s) not found:', missing.join(', '));
    process.exit(3);
  }
  const os = require('os');
  const tmpDir = path.join(os.tmpdir(), `gocd-css-convert-${Date.now()}`);
  console.log('Entry-point mode: ' + entryRelPaths.join(', '));
  console.log('Preparing: copying source to temp dir...');
  if (fs.cpSync) {
    fs.cpSync(inputDir, tmpDir, { recursive: true });
  } else {
    copyRecursiveSync(inputDir, tmpDir);
  }
  console.log('Copy done. Applying stubs...');
  const stubMixins = path.join(stubsDir, 'shared', '_mixins.scss');
  const targetMixins = path.join(tmpDir, 'shared', '_mixins.scss');
  mkdirp.sync(path.dirname(targetMixins));
  fs.copyFileSync(stubMixins, targetMixins);
  // Root-level stubs so "font-awesome-sprockets" etc. resolve from single_page_apps/
  for (const name of ['_font-awesome-sprockets.scss', '_font-awesome-glyphs.scss', 'foundation_and_overrides.scss']) {
    const src = path.join(stubsDir, name);
    if (fs.existsSync(src)) fs.copyFileSync(src, path.join(tmpDir, name));
  }
  mkdirp.sync(outputDir);
  removeKnownOutputs(outputDir);
  console.log(`Compiling ${entries.length} entry point(s)...`);
  return Promise.all(
    entries.map((entryPath, i) => {
      const rel = path.relative(inputDir, entryPath);
      const base = path.basename(entryPath, '.scss');
      console.log(`  [${i + 1}/${entries.length}] ${base}.scss`);
      const entryInTmp = path.join(tmpDir, rel);
      const outPath = path.join(outputDir, `${base}.css`);
      return processOne(entryInTmp, outPath, tmpDir);
    })
  ).then(() => {
    console.log('Cleaning up temp dir...');
    try { fs.rmSync(tmpDir, { recursive: true }); } catch (_) {}
  });
}

function globMode() {
  const pattern = path.join(inputDir, '**/*.scss');
  const all = glob.sync(pattern, { nodir: true });
  const exclude = new Set([
    'frameworks.scss',
    path.join(inputDir, 'frameworks.scss'),
  ]);
  const files = all.filter(f => {
    const name = path.basename(f);
    if (exclude.has(name) || exclude.has(f)) return false;
    return true;
  });
  if (files.length === 0) {
    console.log('No .scss files to convert (after exclusions).');
    return Promise.resolve();
  }
  console.log(`Converting ${files.length} file(s) from ${inputDir} → ${outputDir}`);
  const loadPaths = buildLoadPaths(inputDir);
  return Promise.all(
    files.map(async (file) => {
      const rel = path.relative(inputDir, file);
      const outPath = path.join(outputDir, rel).replace(/\.scss$/, '.css');
      try {
        const result = sass.compile(file, { style: 'expanded', loadPaths });
        let css = result.css;
        const post = await postcss([autoprefixer]).process(css, { from: undefined });
        css = post.css;
        const header = `/* Converted from: ${rel} */\n`;
        mkdirp.sync(path.dirname(outPath));
        fs.writeFileSync(outPath, header + css, 'utf8');
        console.log(`Wrote ${outPath}`);
      } catch (err) {
        console.error(`Error processing ${file}:`, err.message);
        throw err;
      }
    })
  );
}

(async () => {
  try {
    if (entryRelPaths.length > 0) {
      await entryPointMode();
    } else {
      await globMode();
    }
    console.log('Conversion complete.');
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
})();
