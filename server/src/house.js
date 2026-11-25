// «Смета дома»: a house described by a few choices (size, floors, foundation, walls, roof, facade, finish, engineering)
// becomes a full estimate — real quantities from the geometry, works with their materials, machines by the shift,
// delivery by the trip — priced by the city's weekly price book (real offers with links). The answer has the same
// shape as «Смета по документам», so the app shows it with the same screen, purchase list and commercial proposal.
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { ApiError } from './util.js';
import { normalizePlace } from './market.js';
import { CATALOG, BY_CODE } from './house-catalog.js';
import { totals } from './smeta.js';

// ---------- input ----------

const pick = (v, allowed, d) => (allowed.includes(v) ? v : d);
const clamp = (v, min, max, d) => { const x = Number(v); return Number.isFinite(x) ? Math.min(Math.max(x, min), max) : d; };

export function cleanParams(body = {}) {
  const e = body.engineering || {};
  const p = {
    length: clamp(body.length, 4, 40, 12), width: clamp(body.width, 4, 30, 10),
    floors: Math.round(clamp(body.floors, 1, 3, 1)), floorHeight: clamp(body.floorHeight, 2.4, 4, 2.8),
    foundation: pick(body.foundation, ['strip', 'slab', 'piles'], 'strip'),
    walls: pick(body.walls, ['gasblock', 'brick', 'ceramic', 'frame', 'timber'], 'gasblock'),
    slabs: pick(body.slabs, ['monolith', 'wood'], 'monolith'),
    roof: pick(body.roof, ['gable', 'hip', 'flat'], 'gable'),
    roofCover: pick(body.roofCover, ['metaltile', 'softroof', 'profroof', 'seamroof'], 'metaltile'),
    pitch: clamp(body.pitch, 10, 45, 30),
    facade: pick(body.facade, ['plaster', 'facing', 'siding', 'none'], 'plaster'),
    finish: pick(body.finish, ['shell', 'rough', 'turnkey'], 'rough'),
    engineering: {
      electric: e.electric !== false, water: e.water !== false,
      sewer: pick(e.sewer, ['septic', 'central', 'none'], 'septic'),
      heating: pick(e.heating, ['gas', 'electric', 'none'], 'gas'),
      well: e.well === true,
    },
    bathrooms: body.bathrooms == null ? null : Math.round(clamp(body.bathrooms, 0, 6, 1)),
    city: String(body.city ?? '').trim().slice(0, 60) || 'Москва',
    title: String(body.title ?? '').trim().slice(0, 120),
    options: { vat: Boolean(body.options?.vat), vatPct: 22, contingencyPct: clamp(body.options?.contingencyPct, 0, 30, 5), deliveryPct: 0, deliveryMode: 'lines' },
  };
  if (p.width > p.length) [p.length, p.width] = [p.width, p.length];
  return p;
}

const r2 = (x) => Math.round(x * 100) / 100;
const up = (x) => Math.ceil(x - 1e-9);

// ---------- geometry → quantities ----------

const WALL = {
  gasblock: { title: 'газобетон D500, 400 мм', thick: 0.4, heavy: true },
  brick: { title: 'кирпич, 510 мм', thick: 0.51, heavy: true },
  ceramic: { title: 'керамоблок, 380 мм', thick: 0.38, heavy: true },
  frame: { title: 'каркас 150 мм с утеплением', thick: 0.2, heavy: false },
  timber: { title: 'брус 150 мм', thick: 0.15, heavy: false },
};
const LABEL = {
  foundation: { strip: 'ленточный', slab: 'монолитная плита', piles: 'винтовые сваи' },
  roof: { gable: 'двускатная', hip: 'вальмовая', flat: 'плоская' },
  roofCover: { metaltile: 'металлочерепица', softroof: 'гибкая черепица', profroof: 'профнастил', seamroof: 'фальцевая' },
  facade: { plaster: 'декоративная штукатурка', facing: 'облицовочный кирпич', siding: 'сайдинг', none: 'без отделки' },
  finish: { shell: 'коробка', rough: 'черновая (white box)', turnkey: 'под ключ' },
};

/** All quantities of the house, each with how it was counted (shown as «основание» in the estimate). */
export function geometry(p) {
  const { length: L, width: W, floors: F, floorHeight: H } = p;
  const wall = WALL[p.walls];
  const P = 2 * (L + W), S0 = L * W, area = S0 * F;
  const rad = (p.pitch * Math.PI) / 180;
  const gables = p.roof === 'gable' ? 2 * 0.5 * W * (W / 2) * Math.tan(rad) : 0;
  const windows = r2(area * 0.14);
  const extDoors = area > 120 ? 2 : 1;
  const intDoors = Math.max(2, Math.round(area / 14));
  const bearing = S0 > 60 ? L : 0; // one inner bearing wall along the house
  const extGross = P * H * F + gables;
  const extNet = Math.max(extGross - windows - extDoors * 2.1, 0);
  const partitionLen = 0.35 * S0;
  const partitions = Math.max(partitionLen * H * F - intDoors * 1.6, 0);
  const bathrooms = p.bathrooms ?? Math.max(1, Math.round(area / 70));
  const over = 0.5;
  const roofPlan = p.roof === 'flat' ? S0 : (L + 2 * over) * (W + 2 * over);
  const roofArea = p.roof === 'flat' ? S0 + 0.6 * P : roofPlan / Math.cos(rad);
  const gutters = p.roof === 'gable' ? 2 * (L + 2 * over) : p.roof === 'hip' ? 2 * (L + W + 4 * over) : 0;
  return { L, W, F, H, P, S0, area, gables, windows, extDoors, intDoors, bearing, extGross, extNet, partitionLen, partitions, bathrooms, roofArea, gutters, wall };
}

// ---------- prices ----------

const priceDir = () => path.join(config.dataDir, 'house-prices');
export const slug = (city) => normalizePlace(city).replace(/[^a-zа-я0-9]+/g, '-').replace(/^-|-$/g, '') || 'city';

export function loadBooks() {
  try {
    return fs.readdirSync(priceDir()).filter((f) => f.endsWith('.json')).flatMap((f) => {
      try { return [JSON.parse(fs.readFileSync(path.join(priceDir(), f), 'utf8'))]; } catch { return []; }
    });
  } catch { return []; }
}

function distanceKm(a, b) {
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 12_742 * Math.asin(Math.sqrt(h));
}

const median = (xs) => { const s = [...xs].sort((a, b) => a - b); return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : 0; };

/** Prices for a city: its own weekly book, else the nearest one within 300 km, else the Russian median; per item. */
export function resolvePrices(city, lat, lon) {
  const books = loadBooks();
  const own = books.find((b) => normalizePlace(b.city) === normalizePlace(city));
  let near = null;
  if (!own && Number.isFinite(lat) && Number.isFinite(lon)) {
    near = books.filter((b) => Number.isFinite(b.lat) && Number.isFinite(b.lon)).map((b) => ({ b, d: distanceKm({ lat, lon }, b) }))
      .filter((x) => x.d <= 300).sort((x, y) => x.d - y.d)[0] || null;
  }
  const book = own || near?.b || null;
  const russia = (code) => {
    const xs = books.map((b) => b.items?.[code]).filter((x) => x && x.typical > 0);
    return xs.length >= 2 ? { low: median(xs.map((x) => x.low)), typical: median(xs.map((x) => x.typical)), high: median(xs.map((x) => x.high)), sources: [], cities: xs.length } : null;
  };
  return {
    city: book?.city || null, coverage: own ? 'city' : near ? 'nearby' : 'national', distanceKm: near ? Math.round(near.d) : undefined, updatedAt: book?.updatedAt || null,
    get(code) {
      const item = BY_CODE.get(code);
      const real = book?.items?.[code];
      if (real && real.typical > 0) return { low: real.low || real.typical, typical: real.typical, high: real.high || real.typical, example: real.example || '', sources: (real.sources || []).slice(0, 3), missing: false };
      const ru = russia(code);
      if (ru) return { ...ru, example: '', missing: false, estimated: true, note: `Медиана по ${ru.cities} городам России` };
      return { low: Math.round(item.base * 0.85), typical: item.base, high: Math.round(item.base * 1.2), example: '', sources: [], missing: false, estimated: true, note: 'Ориентир: реальных предложений по городу ещё нет' };
    },
  };
}

// ---------- the estimate ----------

/** Lines of the estimate: works with their materials, then machines and delivery trips. */
export function lines(p) {
  const g = geometry(p);
  const { L, W, F, H, P, S0, area, wall } = g;
  const works = [];
  const W_ = (section, code, quantity, basis, materials = []) => {
    if (!(quantity > 0)) return;
    works.push({ section, code, quantity: r2(quantity), basis, materials: materials.filter((m) => m.quantity > 0).map((m) => ({ ...m, quantity: m.unit === 'шт' || m.unit === 'мешок' ? up(m.quantity) : r2(m.quantity) })) });
  };
  const M = (code, quantity, note = '') => ({ code, unit: BY_CODE.get(code).unit, quantity, note });
  const t = { sand: 0, gravel: 0, steel: 0, wood: 0, blocks: 0, roof: 0, bags: 0, finish: 0 };
  let excavation = 0, pours = 0;

  // Подготовительные
  W_('Подготовительные работы', 'w_layout', 1, 'разбивка осей и вынос в натуру');
  W_('Подготовительные работы', 'w_site', 1, 'бытовка, временный щит на период строительства');

  // Фундамент
  const F_ = 'Фундамент';
  if (p.foundation === 'strip') {
    const len = P + g.bearing, h = 1.5, b = 0.4;
    const conc = len * b * h * 1.02;
    excavation += len * 0.8 * 1.3;
    W_('Земляные работы', 'w_dig', len * 0.8 * 1.3, `траншея ${r2(len)} м.п. × 0,8 × 1,3 м`);
    W_(F_, 'w_cushion', len * 0.8 * 0.2, 'подушка 200 мм под ленту', [M('sand', len * 0.8 * 0.2 * 1.2)]);
    W_(F_, 'w_strip', conc, `лента ${r2(len)} м.п. × ${b} × ${h} м (периметр ${r2(P)} м${g.bearing ? ' + внутренняя несущая' : ''})`,
      [M('concrete', conc), M('rebar', conc * 0.08), M('board', 2 * len * h * 0.025 * 0.5, 'опалубка, оборачиваемость 2')]);
    W_(F_, 'w_waterproof', len * (h + b), 'боковая и горизонтальная гидроизоляция ленты', [M('waterproof', len * (h + b) * 1.15)]);
    const floorConc = S0 * 0.1;
    W_(F_, 'w_floor', floorConc, `бетонный пол по грунту 100 мм внутри ленты, ${r2(S0)} м²`, [M('concrete', floorConc), M('rebar', S0 * 0.005), M('sand', S0 * 0.2 * 1.2), M('xps', S0)]);
    t.sand += (len * 0.8 * 0.2 + S0 * 0.2) * 1.2 * 1.6; t.steel += conc * 0.08 + S0 * 0.005; t.wood += 2 * len * h * 0.025 * 0.5 * 0.55;
    pours += 2;
  } else if (p.foundation === 'slab') {
    const A = (L + 0.6) * (W + 0.6), conc = A * 0.3 * 1.02;
    excavation += A * 0.5;
    W_('Земляные работы', 'w_dig', A * 0.5, `котлован под плиту ${r2(A)} м² × 0,5 м`);
    W_(F_, 'w_cushion', A * 0.4, 'подушка: песок 300 мм + щебень 100 мм', [M('sand', A * 0.3 * 1.2), M('gravel', A * 0.1 * 1.2)]);
    W_(F_, 'w_slab', conc, `плита ${r2(L + 0.6)} × ${r2(W + 0.6)} м × 300 мм`, [M('concrete', conc), M('rebar', conc * 0.11), M('xps', A), M('board', (2 * (L + W + 1.2)) * 0.3 * 0.025)]);
    W_(F_, 'w_waterproof', A, 'гидроизоляция под плиту', [M('waterproof', A * 1.15)]);
    t.sand += A * 0.3 * 1.2 * 1.6; t.gravel += A * 0.1 * 1.2 * 1.4; t.steel += conc * 0.11; pours += 1;
  } else {
    const count = up(P / 2) + up(g.bearing / 2.5) + up(S0 / 9);
    const gr = P + g.bearing + W * up(L / 3);
    W_(F_, 'w_piles', count, `шаг 2 м по периметру и несущей + поле под пол (${r2(S0)} м²)`, [M('pile', count)]);
    W_(F_, 'w_grillage', gr, 'обвязка брусом 150×200 по сваям и лагам', [M('lumber', gr * 0.15 * 0.2 * 1.1)]);
    t.steel += count * 0.03; t.wood += gr * 0.15 * 0.2 * 0.5;
  }

  // Стены и перегородки
  const S_ = 'Стены и перегородки';
  const inner = g.bearing * H * F;
  if (wall.heavy) {
    const code = { gasblock: 'w_gasblock', brick: 'w_brick', ceramic: 'w_ceramic' }[p.walls];
    const vol = (g.extNet * wall.thick + inner * (p.walls === 'gasblock' ? 0.3 : 0.38)) * 1.04;
    const mats = p.walls === 'gasblock' ? [M('gasblock', vol), M('glue', vol * 1.1)]
      : p.walls === 'brick' ? [M('brick', vol * 394), M('mortar', vol * 17)]
        : [M('ceramic', vol), M('mortar', vol * 7)];
    W_(S_, code, vol, `наружные ${r2(g.extNet)} м² за вычетом окон и дверей × ${wall.thick} м${inner ? ` + несущая ${r2(inner)} м²` : ''}${g.gables ? ' (с фронтонами)' : ''}`, mats);
    t.blocks += vol * (p.walls === 'gasblock' ? 0.55 : p.walls === 'brick' ? 1.8 : 0.8); t.bags += vol * (p.walls === 'gasblock' ? 1.1 : p.walls === 'brick' ? 17 : 7) * 0.025;
    const belt = P * 0.4 * 0.25 * F;
    W_(S_, 'w_belt', belt, `армопояс по периметру на каждом этаже: ${r2(P)} м × 0,4 × 0,25 × ${F}`, [M('concrete', belt), M('rebar', belt * 0.1)]);
    t.steel += belt * 0.1;
    const partVol = g.partitions * 0.1 * 1.05;
    W_(S_, 'w_partition', g.partitions, `перегородки из газобетона 100 мм: ≈${r2(g.partitionLen)} м.п. на этаж`, [M('gasblock', partVol), M('glue', partVol * 1.1)]);
    t.blocks += partVol * 0.55;
  } else if (p.walls === 'frame') {
    const a = g.extNet + inner;
    W_(S_, 'w_frame', a, `каркасные стены ${r2(a)} м²: стойки 50×150, утеплитель 150–200 мм, OSB снаружи`,
      [M('lumber', a * 0.045), M('wool', a * 2), M('osb', a * 1.1), M('membrane', a * 2.2)]);
    W_(S_, 'w_partition', g.partitions, 'каркасные перегородки со звукоизоляцией', [M('lumber', g.partitions * 0.02), M('wool', g.partitions)]);
    t.wood += (a * 0.045 + g.partitions * 0.02) * 0.5 + a * 1.1 * 0.008;
  } else {
    const vol = (g.extNet + inner) * 0.15 * 1.1;
    W_(S_, 'w_timber', vol, `стены из бруса 150 мм: ${r2(g.extNet + inner)} м²`, [M('timber', vol), M('wool', (g.extNet + inner) * 0.1)]);
    W_(S_, 'w_partition', g.partitions, 'каркасные перегородки', [M('lumber', g.partitions * 0.02), M('wool', g.partitions)]);
    t.wood += vol * 0.5 + g.partitions * 0.02 * 0.5;
  }

  // Перекрытия
  const O_ = 'Перекрытия';
  if (F > 1) {
    const a = S0 * (F - 1);
    if (p.slabs === 'monolith' && wall.heavy) {
      const c = a * 0.2;
      W_(O_, 'w_monolith', c, `монолит 200 мм, ${r2(a)} м²`, [M('concrete', c), M('rebar', c * 0.12)]);
      t.steel += c * 0.12; pours += F - 1;
    } else {
      W_(O_, 'w_beams', a, `межэтажное по деревянным балкам, ${r2(a)} м²`, [M('lumber', a * 0.06), M('wool', a), M('osb', a * 1.05)]);
      t.wood += a * 0.06 * 0.5;
    }
  }
  if (p.roof !== 'flat') {
    W_(O_, 'w_beams', S0, `чердачное перекрытие по балкам, ${r2(S0)} м²`, [M('lumber', S0 * 0.05), M('membrane', S0 * 1.1)]);
    W_(O_, 'w_attic', S0, 'утепление чердачного перекрытия 200 мм', [M('wool', S0 * 2)]);
    t.wood += S0 * 0.05 * 0.5;
  } else {
    const c = S0 * 0.2;
    W_(O_, 'w_monolith', c, `плита покрытия 200 мм под плоскую кровлю, ${r2(S0)} м²`, [M('concrete', c), M('rebar', c * 0.12)]);
    t.steel += c * 0.12; pours += 1;
  }

  // Кровля
  const K_ = 'Кровля';
  if (p.roof === 'flat') {
    W_(K_, 'w_flatroof', g.roofArea, `плоская кровля ${r2(g.roofArea)} м² с парапетом: XPS 200 мм, разуклонка, 2 слоя мембраны`, [M('xps', S0 * 2), M('waterproof', g.roofArea * 2.3)]);
  } else {
    W_(K_, 'w_rafters', g.roofArea, `${LABEL.roof[p.roof]}, уклон ${p.pitch}°, со свесами 0,5 м: ${r2(g.roofArea)} м² по скатам`, [M('lumber', g.roofArea * 0.04), M('membrane', g.roofArea * 1.15)]);
    const cover = [M(p.roofCover, g.roofArea * 1.1)];
    if (p.roofCover === 'softroof') cover.push(M('osb', g.roofArea * 1.05));
    W_(K_, 'w_roofing', g.roofArea, `${LABEL.roofCover[p.roofCover]}, запас 10 % на подрезку`, cover);
    W_(K_, 'w_gutter', g.gutters, 'желоба по свесам, водосточные трубы по углам', [M('gutter', g.gutters)]);
    t.wood += g.roofArea * 0.04 * 0.5 + (p.roofCover === 'softroof' ? g.roofArea * 0.008 : 0);
    t.roof += g.roofArea * 1.1 * (p.roofCover === 'softroof' ? 0.01 : 0.005);
  }

  // Окна и двери
  const D_ = 'Окна и двери';
  W_(D_, 'w_window', g.windows, `остекление ≈14 % площади дома (норма естественного света): ${r2(g.windows)} м²`, [M('window', g.windows)]);
  W_(D_, 'w_door_ext', g.extDoors, g.extDoors > 1 ? 'главный вход и выход на участок' : 'главный вход', [M('door_ext', g.extDoors)]);
  if (p.finish === 'turnkey') W_(D_, 'w_door_int', g.intDoors, `≈1 дверь на 14 м² дома`, [M('door_int', g.intDoors)]);

  // Фасад
  const facadeArea = g.extNet;
  if (p.facade === 'plaster' && p.walls !== 'timber') W_('Фасад', 'w_facade_plaster', facadeArea, `фасад ${r2(facadeArea)} м² за вычетом проёмов`, [M('facade_plaster', facadeArea * 1.05)]);
  if (p.facade === 'facing') { W_('Фасад', 'w_facing', facadeArea, `облицовка в полкирпича ${r2(facadeArea)} м²`, [M('facing_brick', facadeArea * 51), M('mortar', facadeArea * 4)]); t.blocks += facadeArea * 51 * 0.0025; t.bags += facadeArea * 4 * 0.025; }
  if (p.facade === 'siding') W_('Фасад', 'w_siding', facadeArea, `сайдинг по обрешётке ${r2(facadeArea)} м²`, [M('siding', facadeArea * 1.08)]);

  // Инженерные системы
  const E_ = 'Инженерные системы', e = p.engineering;
  if (e.electric) W_(E_, 'w_electric', area, `электрика на ${r2(area)} м²: щит, кабель, розетки, свет`, [M('electric_mat', area)]);
  const points = g.bathrooms * 4 + 2;
  if (e.water) W_(E_, 'w_plumb', points, `${g.bathrooms} с/у × 4 точки + кухня 2 точки`, [M('plumb_mat', points)]);
  if (e.heating !== 'none') {
    const rads = up(area / 12);
    W_(E_, 'w_heating', rads, `радиатор на ≈12 м²: ${rads} шт.`, [M('radiator', rads)]);
    W_(E_, 'w_boiler', 1, e.heating === 'gas' ? 'газовый котёл (без подключения к газу — ТУ отдельно)' : 'электрокотёл', [M(e.heating === 'gas' ? 'boiler' : 'eboiler', 1)]);
  }
  if (e.sewer === 'septic') W_(E_, 'w_septic', 1, 'автономная канализация', [M('septic', 1)]);
  if (e.well) W_(E_, 'w_well', 40, 'скважина ≈40 м (глубина уточняется по участку)', [M('pump', 1)]);

  // Внутренняя отделка
  const I_ = 'Внутренняя отделка';
  if (p.finish !== 'shell') {
    // Plaster «по маякам» — only on masonry; frame and timber walls are sheathed, not plastered.
    const plaster = wall.heavy ? (g.extNet - g.gables) + inner * 2 + g.partitions * 2 : 0;
    if (plaster > 0) { W_(I_, 'w_plaster', plaster, 'штукатурка стен по маякам (кладочные стены)', [M('gypsum', plaster * 10 / 30)]); t.bags += plaster * 10 / 1000; }
    // Screed only on concrete: the ground floor on a strip or slab, and monolithic floors upstairs. Piles — a wooden floor.
    const screed = (p.foundation === 'piles' ? 0 : S0) + (p.slabs === 'monolith' && wall.heavy ? S0 * (F - 1) : 0);
    if (screed > 0) W_(I_, 'w_screed', screed, `стяжка 50 мм: ${r2(screed)} м²`, [M('screed_mix', screed * 2.5)]);
    if (screed > 0) t.bags += screed * 2.5 * 0.04;
    if (p.finish === 'turnkey') {
      const tileFloor = g.bathrooms * 6, tileWalls = g.bathrooms * 20 + 3;
      W_(I_, 'w_tile', tileFloor + tileWalls, `с/у: пол ${tileFloor} м² + стены ${tileWalls} м² (с фартуком кухни)`, [M('tile', (tileFloor + tileWalls) * 1.1)]);
      W_(I_, 'w_laminate', Math.max(area - tileFloor, 0), 'ламинат в комнатах', [M('laminate', Math.max(area - tileFloor, 0) * 1.07)]);
      const paint = Math.max((wall.heavy ? plaster : (g.extNet + g.partitions * 2)) - tileWalls, 0);
      W_(I_, 'w_paint', paint, 'шпаклёвка и покраска стен', [M('paint_set', paint)]);
      W_(I_, 'w_ceiling', area, 'натяжные потолки', []);
      t.finish += (tileFloor + tileWalls) * 0.025 + area * 0.009;
    }
  }

  // Техника и доставка — as they are really hired: shifts, outings, trips.
  const logistics = [];
  const L_ = (code, quantity, basis) => { if (quantity > 0) logistics.push({ code, quantity: up(quantity), basis }); };
  if (excavation > 0) L_('m_excavator', Math.max(1, excavation / 250), `${r2(excavation)} м³ грунта, ≈250 м³ за смену`);
  L_('m_pump', pours, `${pours} заливк${pours === 1 ? 'а' : 'и'}: фундамент${pours > 1 ? ', плиты перекрытий' : ''}`);
  L_('d_dump', (t.sand + t.gravel) / 20, `${r2(t.sand + t.gravel)} т песка и щебня`);
  L_('d_long', (t.steel + t.wood) / 10, `${r2(t.steel)} т арматуры и металла, ${r2(t.wood)} т пиломатериала`);
  const pallets = t.blocks + t.roof + (t.bags > 3 ? t.bags : 0);
  L_('d_manip', pallets / 10, `${r2(pallets)} т на поддонах: блоки/кирпич${t.roof ? ', кровля' : ''}${t.bags > 3 ? ', смеси в мешках' : ''}`);
  const van = t.finish + (t.bags > 3 ? 0 : t.bags);
  L_('d_van', van > 0.05 ? Math.max(1, van / 1.5) : 0, 'отделочные материалы и мелочь');
  return { geometry: g, works, logistics };
}

const SECTION_ORDER = ['Подготовительные работы', 'Земляные работы', 'Фундамент', 'Стены и перегородки', 'Перекрытия', 'Кровля', 'Окна и двери', 'Фасад', 'Инженерные системы', 'Внутренняя отделка'];

export function estimate(body, { lat, lon } = {}) {
  const p = cleanParams(body);
  if (p.foundation === 'piles' && WALL[p.walls].heavy) throw new ApiError(400, 'Винтовые сваи не подходят под тяжёлые стены (газобетон, кирпич, керамоблок). Выберите ленту или плиту — или каркас/брус.');
  const { geometry: g, works, logistics } = lines(p);
  const prices = resolvePrices(p.city, lat, lon);
  const zero = () => ({ low: 0, typical: 0, high: 0 });
  const add = (t, pr, q) => { t.low += pr.low * q; t.typical += pr.typical * q; t.high += pr.high * q; };
  const purchase = new Map();
  let realCount = 0, totalCount = 0;
  const seen = new Set();
  const count = (code, pr) => { if (seen.has(code)) return; seen.add(code); totalCount += 1; if (!pr.estimated) realCount += 1; };

  const sections = new Map();
  const numbering = new Map();
  for (const w of works) {
    const s = sections.get(w.section) || { title: w.section, works: zero(), materials: zero(), machines: zero(), items: [] };
    const n = (numbering.get(w.section) || 0) + 1; numbering.set(w.section, n);
    const item = BY_CODE.get(w.code);
    const price = prices.get(w.code); count(w.code, price);
    add(s.works, price, w.quantity);
    const materials = w.materials.map((m) => {
      const mi = BY_CODE.get(m.code);
      const mp = prices.get(m.code); count(m.code, mp);
      add(s.materials, mp, m.quantity);
      const line = purchase.get(m.code) || { key: m.code, name: mi.name, unit: mi.unit, quantity: 0, price: mp };
      line.quantity = r2(line.quantity + m.quantity); purchase.set(m.code, line);
      return { name: mi.name, unit: mi.unit, quantity: m.quantity, price: mp, sum: r2(mp.typical * m.quantity) };
    });
    const laborSum = r2(price.typical * w.quantity);
    s.items.push({ id: `${SECTION_ORDER.indexOf(w.section) + 1}.${n}`, section: w.section, name: item.name.replace(/ \(работа[^)]*\)| \(на [^)]*\)/g, ''), unit: item.unit, quantity: w.quantity, basis: w.basis, confidence: 'medium', price, materials, machines: [], laborSum, sum: r2(laborSum + materials.reduce((t, m) => t + m.sum, 0)) });
    sections.set(w.section, s);
  }
  const ordered = SECTION_ORDER.filter((t) => sections.has(t)).map((t) => sections.get(t));
  const machinesRange = zero(), deliveryRange = zero();
  if (logistics.length) {
    const s = { title: 'Техника и доставка', works: zero(), materials: zero(), machines: zero(), items: [] };
    logistics.forEach((l, i) => {
      const item = BY_CODE.get(l.code);
      const price = prices.get(l.code); count(l.code, price);
      add(s.machines, price, l.quantity);
      add(item.kind === 'delivery' ? deliveryRange : machinesRange, price, l.quantity);
      const sum = r2(price.typical * l.quantity);
      s.items.push({ id: `Т${i + 1}`, section: s.title, name: item.name, unit: item.unit, quantity: l.quantity, basis: l.basis, confidence: 'medium', price, materials: [], machines: [], laborSum: sum, sum });
    });
    ordered.push(s);
  }

  const where = prices.coverage === 'city' ? `г. ${prices.city}` : prices.coverage === 'nearby' ? `ближайший город с ценами — ${prices.city} (${prices.distanceKm} км)` : 'медиана по городам России';
  const date = prices.updatedAt ? String(prices.updatedAt).slice(0, 10).split('-').reverse().join('.') : null;
  const title = p.title || `Дом ${r2(g.L)}×${r2(g.W)} м, ${p.floors} эт., ${r2(g.area)} м²`;
  return {
    title, city: p.city, createdAt: new Date().toISOString(),
    object: { name: title, type: 'Жилой дом', area: r2(g.area), floors: p.floors, summary: `${title}: стены — ${WALL[p.walls].title}, фундамент — ${LABEL.foundation[p.foundation]}, кровля — ${LABEL.roof[p.roof]} (${LABEL.roofCover[p.roofCover]}), фасад — ${LABEL.facade[p.facade]}, отделка — ${LABEL.finish[p.finish]}.` },
    sections: ordered,
    materials: [...purchase.values()],
    machines: ordered.find((s) => s.title === 'Техника и доставка')?.items.map((i) => ({ key: i.id, name: i.name, unit: i.unit, quantity: i.quantity, price: i.price })) || [],
    totals: totals(ordered, p.options, { machines: machinesRange, delivery: deliveryRange }),
    options: p.options,
    assumptions: [
      `Цены: ${where}${date ? `, обновлены ${date}` : ''}. Реальные предложения со ссылками — ${realCount} из ${totalCount} позиций; остальные — ориентир (помечены *).`,
      `Геометрия: периметр ${r2(g.P)} м, пятно ${r2(g.S0)} м², высота этажа ${g.H} м, остекление ${r2(g.windows)} м², перегородки ≈${r2(g.partitionLen)} м.п. на этаж. Объёмы посчитаны по размерам, а не «на квадратный метр».`,
      'Не входит: проект и согласования, подключение к сетям (газ, электричество, вода), благоустройство участка, мебель и техника.',
      ...(p.walls === 'timber' && p.facade === 'plaster' ? ['Брус по фасаду не штукатурится — фасад оставлен без отделки.'] : []),
    ],
    discrepancies: [],
    audit: { verdict: '', issues: [], added: 0 },
    sources: [],
    unpriced: 0,
    params: p,
    prices: { city: prices.city, coverage: prices.coverage, updatedAt: prices.updatedAt, real: realCount, total: totalCount },
  };
}

/** Cities people estimate houses in: the weekly collection prices them first (demand decides, not a fixed list). */
export function noteDemand(city, lat, lon) {
  const name = String(city || '').trim().slice(0, 60);
  if (!name) return;
  try {
    const file = path.join(config.dataDir, 'house-demand.json');
    let list = {};
    try { list = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { /* first time */ }
    const k = normalizePlace(name);
    const item = list[k] || { city: name, count: 0 };
    item.count += 1; item.lastAt = new Date().toISOString();
    if (Number.isFinite(lat) && Number.isFinite(lon)) { item.lat = Math.round(lat * 100) / 100; item.lon = Math.round(lon * 100) / 100; }
    list[k] = item;
    fs.mkdirSync(config.dataDir, { recursive: true });
    fs.writeFileSync(`${file}.tmp`, JSON.stringify(list, null, 2)); fs.renameSync(`${file}.tmp`, file);
  } catch (error) { console.error('house-demand:', error.message); }
}

export { CATALOG };
