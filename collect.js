// collect-files.js
const fs = require('fs');
const path = require('path');

const OUTPUT_FILE = 'collected_files.txt';
const ROOT_DIR = process.cwd();

// Каталоги, которые не обходим
const SKIP_DIRS = new Set([
  'node_modules', '.git', '.hg', '.svn',
  '.idea', '.vscode',
  'dist', 'build', 'out', '.next', 'coverage',
]);

// Единственное исключение из «всех файлов» — .docx
const SKIP_EXTENSIONS = new Set(['.docx']);

// Проверка на бинарный файл: ищем нулевые байты в первых 8 КБ
function isBinary(buffer) {
  const len = Math.min(buffer.length, 8000);
  for (let i = 0; i < len; i++) {
    if (buffer[i] === 0) return true;
  }
  return false;
}

function findFiles(dir, result = []) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      if (SKIP_DIRS.has(entry.name)) continue;
      findFiles(fullPath, result);
    } else if (entry.isFile()) {
      // не включаем сам вывод
      if (path.resolve(fullPath) === path.resolve(ROOT_DIR, OUTPUT_FILE)) continue;

      const ext = path.extname(entry.name).toLowerCase();
      if (SKIP_EXTENSIONS.has(ext)) continue;

      result.push(fullPath);
    }
  }

  return result;
}

function readFileContent(filePath) {
  const buffer = fs.readFileSync(filePath);

  if (isBinary(buffer)) {
    return { binary: true, size: buffer.length };
  }

  let content = buffer.toString('utf8');
  // убираем BOM
  if (content.charCodeAt(0) === 0xFEFF) content = content.slice(1);

  return { binary: false, size: buffer.length, content };
}

function main() {
  const files = findFiles(ROOT_DIR);

  if (files.length === 0) {
    console.log('Файлы не найдены.');
    return;
  }

  files.sort();

  const chunks = [];
  let textCount = 0;
  let binaryCount = 0;

  for (const filePath of files) {
    const relative = path.relative(ROOT_DIR, filePath);

    let info;
    try {
      info = readFileContent(filePath);
    } catch (err) {
      console.warn(`Пропущен (ошибка чтения): ${relative} — ${err.message}`);
      continue;
    }

    if (info.binary) {
      binaryCount++;
      const header =
        '='.repeat(80) + '\n' +
        `FILE: ${relative} (BINARY, ${info.size} bytes — content skipped)\n` +
        '='.repeat(80) + '\n';
      chunks.push(header + '\n\n');
      console.log(`Добавлен (binary): ${relative}`);
    } else {
      textCount++;
      const header =
        '='.repeat(80) + '\n' +
        `FILE: ${relative}\n` +
        '='.repeat(80) + '\n';
      chunks.push(header + info.content + '\n\n');
      console.log(`Добавлен: ${relative}`);
    }
  }

  fs.writeFileSync(OUTPUT_FILE, chunks.join(''), { encoding: 'utf8' });

  console.log(`\nГотово! Всего файлов: ${files.length}`);
  console.log(`  текстовых: ${textCount}`);
  console.log(`  бинарных:  ${binaryCount} (содержимое пропущено)`);
  console.log(`Результат: ${path.resolve(OUTPUT_FILE)}`);
}

main();