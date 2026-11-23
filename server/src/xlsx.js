// Minimal .xlsx reader without dependencies: the zip directory, shared strings and every sheet as tab-separated text.
// Enough for estimates and bills of quantities (values, not formatting). Old binary .xls is not supported.
import zlib from 'node:zlib';
import { ApiError } from './util.js';

function unzip(buffer) {
  let end = buffer.length - 22;
  while (end >= 0 && buffer.readUInt32LE(end) !== 0x06054b50) end -= 1;
  if (end < 0) throw new ApiError(400, 'Файл Excel повреждён или это не .xlsx.');
  const count = buffer.readUInt16LE(end + 10);
  let p = buffer.readUInt32LE(end + 16);
  const files = new Map();
  for (let i = 0; i < count; i += 1) {
    if (buffer.readUInt32LE(p) !== 0x02014b50) break;
    const method = buffer.readUInt16LE(p + 10);
    const size = buffer.readUInt32LE(p + 20);
    const nameLength = buffer.readUInt16LE(p + 28);
    const extra = buffer.readUInt16LE(p + 30);
    const comment = buffer.readUInt16LE(p + 32);
    const local = buffer.readUInt32LE(p + 42);
    const name = buffer.toString('utf8', p + 46, p + 46 + nameLength);
    const start = local + 30 + buffer.readUInt16LE(local + 26) + buffer.readUInt16LE(local + 28);
    const raw = buffer.subarray(start, start + size);
    files.set(name, () => (method === 8 ? zlib.inflateRawSync(raw) : raw).toString('utf8'));
    p += 46 + nameLength + extra + comment;
  }
  return files;
}

const decode = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n))).replace(/&amp;/g, '&');
const texts = (xml) => [...xml.matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((m) => decode(m[1])).join('');
const column = (ref) => [...ref.replace(/\d+/g, '')].reduce((n, ch) => n * 26 + ch.charCodeAt(0) - 64, 0) - 1;

/** All sheets of the workbook as text: «## Лист» and rows with cells separated by tabs. */
export function xlsxToText(base64, maxChars = 120_000) {
  const files = unzip(Buffer.from(base64, 'base64'));
  const shared = files.has('xl/sharedStrings.xml') ? [...files.get('xl/sharedStrings.xml')().matchAll(/<si>([\s\S]*?)<\/si>/g)].map((m) => texts(m[1])) : [];
  const workbook = files.has('xl/workbook.xml') ? files.get('xl/workbook.xml')() : '';
  const rels = files.has('xl/_rels/workbook.xml.rels') ? files.get('xl/_rels/workbook.xml.rels')() : '';
  const targets = new Map([...rels.matchAll(/<Relationship[^>]*Id="([^"]+)"[^>]*Target="([^"]+)"/g)].map((m) => [m[1], m[2].replace(/^\/?(xl\/)?/, 'xl/')]));
  let sheets = [...workbook.matchAll(/<sheet[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"/g)].map((m) => ({ name: decode(m[1]), path: targets.get(m[2]) }));
  if (!sheets.length) sheets = [...files.keys()].filter((k) => /^xl\/worksheets\/sheet\d+\.xml$/.test(k)).map((path, i) => ({ name: `Лист ${i + 1}`, path }));
  const out = [];
  for (const sheet of sheets) {
    if (!files.has(sheet.path)) continue;
    out.push(`## ${sheet.name}`);
    for (const row of files.get(sheet.path)().matchAll(/<row[^>]*>([\s\S]*?)<\/row>/g)) {
      const cells = [];
      for (const c of row[1].matchAll(/<c([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
        const attrs = c[1]; const body = c[2] || '';
        const ref = (attrs.match(/r="([A-Z]+\d+)"/) || [])[1];
        const type = (attrs.match(/t="([^"]+)"/) || [])[1];
        const v = (body.match(/<v>([\s\S]*?)<\/v>/) || [])[1];
        let value = '';
        if (type === 's' && v !== undefined) value = shared[Number(v)] ?? '';
        else if (type === 'inlineStr') value = texts(body);
        else if (v !== undefined) value = decode(v);
        const index = ref ? column(ref) : cells.length;
        cells[index] = value.replace(/\s+/g, ' ').trim();
      }
      const line = Array.from(cells, (x) => x ?? '').join('\t').replace(/\t+$/, '');
      if (line.trim()) out.push(line);
    }
    if (out.join('\n').length > maxChars) break;
  }
  const text = out.join('\n').slice(0, maxChars);
  if (!text.replace(/##.*$/gm, '').trim()) throw new ApiError(400, 'В файле Excel не нашлось данных.');
  return text;
}
