// «Металлоконструкции»: a canopy, a frame building (hangar, warehouse, garage) or a fence described by a few choices →
// steel by the metre of every profile (tonnes, as rolled steel is sold), fabrication and erection by the tonne, painting by
// the surface, footings, cladding, gates — and the crane, concrete pump and delivery trips. Priced by the city's weekly
// real prices and returned in the shape of «Смета по документам» (the same screen, purchase list and proposal in the app).
import { ApiError } from './util.js';
import { BY_CODE } from './house-catalog.js';
import { build } from './house.js';

const pick = (v, allowed, d) => (allowed.includes(v) ? v : d);
const clamp = (v, min, max, d) => { const x = Number(v); return Number.isFinite(x) ? Math.min(Math.max(x, min), max) : d; };
const r2 = (x) => Math.round(x * 100) / 100;
const up = (x) => Math.ceil(x - 1e-9);

// kg per metre of the profiles used (ГОСТ 30245, typical wall thickness).
const KG = { p160: 23.7, p120: 14.4, p100: 9.0, p80: 7.1, p60: 5.2, p60x2: 3.6, p40: 2.3, p40x20: 1.7 };
const PAINT_M2_PER_KG = 0.05; // outer surface of profile pipe ≈ 0.04–0.07 m² per kg

export function cleanParams(body = {}) {
  return {
    type: pick(body.type, ['canopy', 'hangar', 'fence'], 'canopy'),
    length: clamp(body.length, 2, 200, 6), width: clamp(body.width, 2, 48, 4), height: clamp(body.height, 1, 12, 2.7),
    roof: pick(body.roof, ['single', 'gable', 'arch'], 'single'),
    cover: pick(body.cover, ['polycarb', 'profroof', 'metaltile'], 'polycarb'),
    walls: pick(body.walls, ['profwall', 'sandwich', 'open'], 'profwall'),
    floor: body.floor !== false,
    gates: Math.round(clamp(body.gates, 0, 6, 1)), wickets: Math.round(clamp(body.wickets, 0, 6, 1)), doors: Math.round(clamp(body.doors, 0, 6, 1)),
    filling: pick(body.filling, ['profwall', 'picket', 'mesh3d'], 'profwall'),
    paint: body.paint !== false,
    city: String(body.city ?? '').trim().slice(0, 60) || 'Москва',
    title: String(body.title ?? '').trim().slice(0, 120),
    options: { vat: Boolean(body.options?.vat), vatPct: 22, contingencyPct: clamp(body.options?.contingencyPct, 0, 30, 5), deliveryPct: 0, deliveryMode: 'lines' },
  };
}

const TITLE = { canopy: 'Навес', hangar: 'Каркасное здание', fence: 'Забор' };
const ROOF = { single: 'односкатная', gable: 'двускатная', arch: 'арочная' };
const COVER = { polycarb: 'поликарбонат', profroof: 'профнастил', metaltile: 'металлочерепица' };
const FILL = { profwall: 'профнастил', picket: 'евроштакетник', mesh3d: '3D‑сетка' };
const ORDER = ['Подготовительные работы', 'Земляные работы и фундамент', 'Металлокаркас', 'Кровля', 'Ограждающие конструкции', 'Забор', 'Ворота и двери', 'Полы'];

export function lines(p) {
  const works = [], logistics = [];
  const W_ = (section, code, quantity, basis, materials = []) => {
    if (!(quantity > 0)) return;
    works.push({ section, code, quantity: r2(quantity), basis, materials: materials.filter((m) => m.quantity > 0).map((m) => ({ ...m, quantity: m.unit === 'шт' ? up(m.quantity) : r2(m.quantity) })) });
  };
  const M = (code, quantity) => ({ code, unit: BY_CODE.get(code).unit, quantity });
  const L_ = (code, quantity, basis) => { if (quantity > 0) logistics.push({ code, quantity: up(quantity), basis }); };
  const steel = { light: 0, heavy: 0 }; // tonnes
  const parts = [];
  const add = (kind, metres, kgPerM, what) => { const t = metres * kgPerM / 1000; steel[kind] += t; parts.push(`${what}: ${r2(metres)} м × ${kgPerM} кг/м`); };
  let concrete = 0, rebar = 0, cladT = 0, pours = 0;
  const { length: L, width: W, height: H } = p;

  if (p.type === 'canopy') {
    const rows = W > 6 ? 3 : 2;
    const perRow = up(L / 3) + 1;
    const posts = rows * perRow;
    const slopeLen = p.roof === 'single' ? W * 1.02 : p.roof === 'gable' ? W * 1.15 : W * 1.22;
    const rise = p.roof === 'single' ? W * 0.18 : 0; // the back row is lower: a 10° slope
    const light = H <= 3.2 && W <= 6;
    add('light', posts * (H + 0.9) + (p.roof === 'single' ? perRow * rise : 0), light ? KG.p80 : KG.p100, `стойки ${light ? '80×80×3' : '100×100×3'} (с заглублением 0,9 м)`);
    add('light', rows * L, KG.p80, 'прогоны по стойкам 80×80×3');
    const trusses = up(L / 1.5) + 1;
    // Up to 6 m a canopy needs plain rafters/arches of 60×40; wider — real trusses (two chords and the web).
    if (W <= 6) add('light', trusses * slopeLen, 2.9, `${p.roof === 'arch' ? 'дуги' : 'стропила'} ${trusses} шт. из трубы 60×40×2`);
    else add('light', trusses * slopeLen * 3, KG.p40, `фермы ${trusses} шт. из трубы 40×40 (пояса и раскосы)`);
    const purlinRows = (up(slopeLen / 0.8) + 1) * (p.roof === 'gable' ? 1 : 1);
    add('light', purlinRows * L, KG.p40x20, 'обрешётка 40×20 с шагом 0,8 м');
    W_('Земляные работы и фундамент', 'w_pillar', posts, `${posts} стоек: бурение Ø200, бетон 0,04 м³ на опору`, [M('concrete', posts * 0.05)]);
    concrete += posts * 0.05;
    const roofArea = (L + 0.6) * (slopeLen + 0.6);
    const coverCode = p.cover;
    W_('Кровля', p.cover === 'polycarb' ? 'w_polycarb' : 'w_roofing', roofArea, `${ROOF[p.roof]} кровля ${r2(roofArea)} м² со свесами 0,3 м`, [M(coverCode, roofArea * 1.1)]);
    W_('Кровля', 'w_gutter', p.roof === 'gable' ? 2 * L : L, 'водосток по свесам', [M('gutter', p.roof === 'gable' ? 2 * L : L)]);
    cladT += roofArea * 1.1 * (BY_CODE.get(coverCode).t || 0.005);
  } else if (p.type === 'hangar') {
    const frames = up(L / 6) + 1; // frames every 6 m
    const rafter = W * 1.02;
    add('heavy', frames * (2 * H + rafter), KG.p160, `рамы ${frames} шт. с шагом 6 м: колонны и ригели 160×160×5`);
    const endPosts = Math.max(up(W / 6) - 1, 0) * 2;
    add('light', endPosts * (H + W * 0.09), KG.p100, 'фахверковые стойки торцов 100×100×3');
    const purlins = up(rafter / 1.2) + 1;
    add('light', purlins * L, KG.p80, `прогоны кровли ${purlins} рядов 80×80×3`);
    const girts = up(H / 1.2);
    add('light', girts * 2 * (L + W), KG.p60, `ригели стен ${girts} рядов 60×60×3`);
    steel.light *= 1.05; steel.heavy *= 1.05; parts.push('связи, фасонка, закладные — +5 %');
    W_('Подготовительные работы', 'w_layout', 1, 'геодезическая разбивка осей колонн');
    const footings = frames * 2 + endPosts;
    const fv = footings * 1.0 * 1.0 * 1.2;
    W_('Земляные работы и фундамент', 'w_footing', fv, `${footings} фундаментов 1,0×1,0×1,2 м под колонны`, [M('concrete', fv), M('rebar', fv * 0.08)]);
    concrete += fv; rebar += fv * 0.08; pours += 1;
    L_('m_excavator', 1, `котлованы под ${footings} фундаментов`);
    const roofArea = (L + 0.6) * (rafter + 0.6);
    const walls = 2 * (L + W) * H + W * W * 0.09 / 2 * 2;
    if (p.walls !== 'open') {
      const code = p.walls;
      W_('Ограждающие конструкции', 'w_cladding', walls, `стены ${r2(walls)} м² (${p.walls === 'sandwich' ? 'сэндвич‑панели 100 мм, тёплый контур' : 'профлист, холодный контур'})`, [M(code, walls * 1.05)]);
      cladT += walls * 1.05 * (BY_CODE.get(code).t || 0.005);
    }
    const roofCode = p.walls === 'sandwich' ? 'sandwich' : 'profroof';
    W_('Кровля', 'w_cladding', roofArea, `двускатная кровля 5–6° ${r2(roofArea)} м² (${roofCode === 'sandwich' ? 'сэндвич‑панели' : 'профнастил'})`, [M(roofCode, roofArea * 1.08)]);
    W_('Кровля', 'w_gutter', 2 * L, 'водосток по свесам', [M('gutter', 2 * L)]);
    cladT += roofArea * 1.08 * (BY_CODE.get(roofCode).t || 0.005);
    if (p.gates) W_('Ворота и двери', 'w_sect_gate', p.gates, 'секционные ворота 4×4 м', [M('sect_gate', p.gates)]);
    if (p.doors) W_('Ворота и двери', 'w_door_ext', p.doors, 'входная дверь', [M('door_ext', p.doors)]);
    if (p.floor) {
      const fl = L * W * 0.15;
      W_('Полы', 'w_floor', fl, `бетонный пол 150 мм, ${r2(L * W)} м², сетка Ø8`, [M('concrete', fl), M('rebar', L * W * 0.006), M('sand', L * W * 0.2 * 1.2)]);
      concrete += fl; rebar += L * W * 0.006; pours += 1;
      L_('d_dump', L * W * 0.2 * 1.2 * 1.6 / 20, `${r2(L * W * 0.24)} м³ песка под пол`);
    }
    const lifts = Math.max(1, (steel.heavy + steel.light) / 6);
    L_('m_crane', lifts, `монтаж ${r2(steel.heavy + steel.light)} т каркаса, ≈6 т за смену`);
  } else {
    const posts = up(L / 2.5) + 1 + p.gates * 2 + p.wickets;
    const rows = H > 2 ? 3 : 2;
    add('light', posts * (H + 1.2), KG.p60x2, `столбы 60×60×2 с шагом 2,5 м (заглубление 1,2 м), ${posts} шт.`);
    add('light', rows * L, KG.p40x20, `лаги 40×20 в ${rows} ряда`);
    W_('Земляные работы и фундамент', 'w_pillar', posts, `${posts} столбов: бурение, бетон 0,04 м³ на столб`, [M('concrete', posts * 0.045)]);
    concrete += posts * 0.045;
    const area = L * H;
    // A fence is assembled on site: the posts and lags are bought as steel and fixed by the fence crew (no workshop fabrication).
    W_('Забор', 'w_fence', L, `${FILL[p.filling]} ${r2(area)} м², высота ${H} м; ${parts.join('; ')}`, [M(p.filling, area * 1.05), M('pipe_light', steel.light * 1.05)]);
    cladT += area * 1.05 * (BY_CODE.get(p.filling).t || 0.005);
    if (p.gates) W_('Ворота и двери', 'w_gate', p.gates, 'распашные ворота 4 м', [M('gate_swing', p.gates)]);
    if (p.wickets) W_('Ворота и двери', 'w_wicket', p.wickets, 'калитка', [M('wicket', p.wickets)]);
    cladT += p.gates * 0.15 + p.wickets * 0.05;
  }

  // Steel: bought by the tonne, made and erected by the tonne, painted by the surface.
  const t = steel.light + steel.heavy;
  const fence = p.type === 'fence';
  const mats = [];
  if (steel.heavy) mats.push(M('pipe_heavy', steel.heavy * 1.05));
  if (steel.light) mats.push(M('pipe_light', steel.light * 1.05));
  if (!fence) {
    W_('Металлокаркас', 'w_fab', t, `${r2(t * 1000)} кг металла: ${parts.join('; ')}; отход на обрезки 5 %`, mats);
    W_('Металлокаркас', 'w_erect', t, 'сборка и установка каркаса на опоры');
  }
  if (p.paint) W_('Металлокаркас', 'w_metal_paint', t * 1000 * PAINT_M2_PER_KG, `≈${PAINT_M2_PER_KG} м² поверхности на кг профиля, грунт‑эмаль 3 в 1`, [M('metal_paint', t * 1000 * PAINT_M2_PER_KG)]);
  if (pours && concrete > 6) L_('m_pump', pours, `${r2(concrete)} м³ бетона`);
  // Up to 1,5 t of 6-metre pipes go on a long «газель»; more (or 12 m) — a long truck.
  const metalT = t * 1.05 + rebar;
  if (metalT > 1.5) L_('d_long', metalT / 10, `${r2(metalT)} т металла (трубы и прокат 6–12 м)`);
  else if (metalT > 0) L_('d_van', 1, `${r2(metalT)} т труб длиной 6 м`);
  if (cladT > 0.05) L_(cladT > 1.5 ? 'd_manip' : 'd_van', cladT > 1.5 ? cladT / 10 : 1, `${r2(cladT)} т листа/панелей/ворот`);
  return { works, logistics, steel: t };
}

export function estimate(body, { lat, lon } = {}) {
  const p = cleanParams(body);
  if (p.type === 'fence' && p.length < 4) throw new ApiError(400, 'Укажите длину забора — от 4 м.');
  const { works, logistics, steel } = lines(p);
  const size = p.type === 'fence' ? `${r2(p.length)} м.п., высота ${p.height} м` : `${r2(p.length)}×${r2(p.width)} м, высота ${p.height} м`;
  const title = p.title || `${TITLE[p.type]} ${size}`;
  const what = p.type === 'canopy' ? `кровля ${ROOF[p.roof]}, ${COVER[p.cover]}`
    : p.type === 'hangar' ? `рамы с шагом 6 м, ${p.walls === 'open' ? 'без стен' : p.walls === 'sandwich' ? 'сэндвич‑панели' : 'профлист'}${p.floor ? ', бетонный пол' : ''}`
      : `${FILL[p.filling]}, ворота ${p.gates}, калитки ${p.wickets}`;
  const area = p.type === 'fence' ? r2(p.length * p.height) : r2(p.length * p.width);
  const result = build({
    works, logistics, order: ORDER, city: p.city, lat, lon, options: p.options, title,
    object: { name: title, type: 'Металлоконструкции', area, floors: 1, summary: `${title}: ${what}. Металл — ${r2(steel * 1000)} кг.` },
    assumptions: [
      `Металл посчитан по длинам каждого профиля и весу метра (ГОСТ 30245): ${r2(steel * 1000)} кг. Сечения — типовые для такого пролёта; окончательно их подтверждает расчёт КМ.`,
      'Не входит: проект КМ/КЖ и согласования, вывоз грунта, электрика и освещение.',
    ],
  });
  return { ...result, params: p };
}
