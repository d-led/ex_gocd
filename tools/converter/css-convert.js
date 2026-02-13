#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const glob = require('glob');
const mkdirp = require('mkdirp');
const sass = require('sass');
const postcss = require('postcss');
const autoprefixer = require('autoprefixer');

function usage() {
  console.log('Usage: node css-convert.js <input_dir> <output_dir>');
  process.exit(1);
}

const args = process.argv.slice(2);
if (args.length < 2) usage();
const inputDir = path.resolve(args[0]);
const outputDir = path.resolve(args[1]);

if (!fs.existsSync(inputDir)) {
  console.error(`Input directory does not exist: ${inputDir}`);
  process.exit(2);
}

console.log(`Converting SCSS from ${inputDir} → ${outputDir}`);

const pattern = path.join(inputDir, '**/*.scss');
const files = glob.sync(pattern, { nodir: true });
if (files.length === 0) {
  console.log('No .scss files found to convert.');
  process.exit(0);
}

async function processFile(file) {
  try {
    const rel = path.relative(inputDir, file);
    const outPath = path.join(outputDir, rel).replace(/\.scss$/, '.css');
    const outDir = path.dirname(outPath);
    mkdirp.sync(outDir);

    // Add all relevant SCSS directories to loadPaths
    const foundationPath = path.resolve(__dirname, 'node_modules/foundation-sites/scss');
    const foundationUtilPath = path.resolve(foundationPath, 'util');
    const loadPaths = [
      inputDir,
      path.dirname(file),
      foundationPath,
      foundationUtilPath,
    ];
    // compile with dart-sass
    const result = sass.compile(file, { style: 'expanded', loadPaths });
    let css = result.css;

    // postcss autoprefixer
    const post = await postcss([autoprefixer]).process(css, { from: undefined });
    css = post.css;

    const header = `/* Converted from: ${file} */\n`;
    fs.writeFileSync(outPath, header + css, 'utf8');
    console.log(`Wrote ${outPath}`);
  } catch (err) {
    console.error(`Error processing ${file}:`, err);
    throw err;
  }
}

(async () => {
  for (const f of files) {
    await processFile(f);
  }
  console.log('Conversion complete.');
})();
