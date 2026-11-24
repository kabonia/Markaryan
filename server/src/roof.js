// «Дом снаружи», этап 0: крыша по 3–5 фото дома.
// ИИ (Gemini 4 Hydrogen через OpenRouter) определяет тип крыши, детали и отмечает на фото ключевые точки фронтона
// (углы стены у земли, углы у карниза, конёк). Уклон и высоту конька считает геометрия: по 4 углам стены строится
// гомография «фото → плоскость стены в метрах» (когда известны ширина стены и высота до карниза — по замеру
// или LiDAR), и точка конька переносится в метры. Без размеров масштаб берётся по двери (стандарт ≈ 2,05 м) —
// ниже точность. У каждого размера метка: measured (дан замер) / photo (геометрия по фото) / assumption.
import { config } from './config.js';
import { ApiError, request, readJSON, parseLooseJSON, outOfFunds } from './util.js';

const MODEL = () => process.env.HOUSE_ROOF_MODEL || 'google/gemini-4-hydrogen';
const DOOR_HEIGHT = 2.05; // м, типичная входная дверь — масштаб «предположение», когда размеров нет

const POINT = { type: 'array', items: { type: 'number' }, description: '[x, y] в долях 0..1000 от ширины и высоты фото; [] если точка не видна' };

const SCHEMA = {
  type: 'object',
  properties: {
    roofType: { type: 'string', description: 'gable | hip | half_hip | mansard | gambrel | shed | flat | pyramid | cross_gable | complex' },
    roofTypeRu: { type: 'string', description: 'по-русски: двускатная, вальмовая, полувальмовая, мансардная (ломаная), односкатная, плоская, шатровая, крестовая, сложная' },
    typeConfidence: { type: 'number', description: '0..1' },
    covering: { type: 'string', description: 'кровельный материал по-русски: металлочерепица, профнастил, мягкая (гибкая) черепица, фальц, керамическая/цементно-песчаная черепица, шифер, ондулин, рулонная…' },
    color: { type: 'string', description: 'цвет кровли по-русски и примерный RAL, если уверенно' },
    details: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          kind: { type: 'string', description: 'dormer | chimney | skylight | gutter | downpipe | snow_guard | valley | overhang | soffit | ridge_vent | antenna | solar | balcony_roof | porch_roof | other' },
          ru: { type: 'string', description: 'что это по-русски' },
          count: { type: 'number' },
          confidence: { type: 'number', description: '0..1' },
          seen: { type: 'boolean', description: 'true — видно на фото; false — предположение (не видно)' },
        },
      },
    },
    photos: {
      type: 'array',
      description: 'по одному элементу на каждое фото, в том же порядке',
      items: {
        type: 'object',
        properties: {
          view: { type: 'string', description: 'что снято: «фасад с фронтоном», «боковой фасад (скат)», «угол дома», «крыша сверху»…' },
          gableVisible: { type: 'boolean', description: 'виден треугольник (фронтон) торцевой стены целиком' },
          frontal: { type: 'boolean', description: 'фронтон снят почти прямо, без сильного ракурса' },
          wallBottomLeft: POINT, wallBottomRight: POINT,
          eaveLeft: POINT, eaveRight: POINT,
          apex: POINT,
          doorTop: POINT, doorBottom: POINT,
          note: { type: 'string' },
        },
      },
    },
    estimate: {
      type: 'object',
      description: 'твоя собственная оценка по фото (метры, градусы); 0 — не знаешь',
      properties: {
        pitchDeg: { type: 'number' }, ridgeHeight: { type: 'number' }, eaveHeight: { type: 'number' },
        gableWidth: { type: 'number' }, overhang: { type: 'number' }, floors: { type: 'number' },
      },
    },
    hidden: { type: 'array', items: { type: 'string' }, description: 'что не видно и поэтому только предположение (задние скаты, ендовы, примыкания…)' },
    advice: { type: 'string', description: 'какое фото доснять, чтобы уточнить (по-русски, коротко)' },
  },
};

const SYSTEM = `Ты — инженер-кровельщик и специалист по фотограмметрии. По нескольким фото одного частного дома, снятым с земли, определи крышу.
1. Тип крыши, кровельный материал, цвет. Детали: слуховые окна, трубы, мансардные окна, водостоки, снегозадержатели, ендовы, свесы, софиты.
2. Для КАЖДОГО фото отметь ключевые точки торцевой стены с фронтоном (если видна) в координатах 0..1000 (x — слева направо, y — сверху вниз):
   wallBottomLeft/Right — углы стены у земли (отмостки), eaveLeft/Right — точки, где верх стены встречает карниз (низ ската, без свеса), apex — конёк (верх треугольника).
   Все пять точек — одной и той же торцевой стены. Если точки не видно — пустой массив, НЕ выдумывай.
   doorTop/doorBottom — середина верха и низа входной двери, если она на этой же стене.
3. Оценка размеров — свои числа, если можешь.
4. hidden — честно перечисли, что не видно. Детали, которые не видно, помечай seen=false.
Если на фото не дом — roofType complex, typeConfidence 0 и объясни в advice.`;

// ---------- геометрия ----------

/** Гомография 3×3 по 4 парам точек (src → dst), DLT с h33 = 1. */
export function homography(src, dst) {
  const A = [];
  const b = [];
  for (let i = 0; i < 4; i += 1) {
    const [x, y] = src[i];
    const [u, v] = dst[i];
    A.push([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.push(u);
    A.push([0, 0, 0, x, y, 1, -v * x, -v * y]); b.push(v);
  }
  const h = solve(A, b);
  if (!h) return null;
  return [[h[0], h[1], h[2]], [h[3], h[4], h[5]], [h[6], h[7], 1]];
}

export function apply(H, [x, y]) {
  const w = H[2][0] * x + H[2][1] * y + H[2][2];
  return [(H[0][0] * x + H[0][1] * y + H[0][2]) / w, (H[1][0] * x + H[1][1] * y + H[1][2]) / w];
}

function solve(A, b) {
  const n = b.length;
  const M = A.map((row, i) => [...row, b[i]]);
  for (let c = 0; c < n; c += 1) {
    let p = c;
    for (let r = c + 1; r < n; r += 1) if (Math.abs(M[r][c]) > Math.abs(M[p][c])) p = r;
    if (Math.abs(M[p][c]) < 1e-12) return null;
    [M[c], M[p]] = [M[p], M[c]];
    for (let r = 0; r < n; r += 1) {
      if (r === c) continue;
      const f = M[r][c] / M[c][c];
      for (let k = c; k <= n; k += 1) M[r][k] -= f * M[c][k];
    }
  }
  return M.map((row, i) => row[n] / row[i]);
}

const ok = (p) => Array.isArray(p) && p.length === 2 && p.every((v) => Number.isFinite(v));
const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const round = (v, d = 2) => (Number.isFinite(v) ? Number(v.toFixed(d)) : null);

/**
 * Фронтон одного фото → уклон и высота конька.
 * `aspect` — ширина/высота фото (точки даны в долях 0..1000 по каждой оси).
 * width/eave — ширина торцевой стены и высота до карниза, м (если известны).
 */
export function gableGeometry(photo, { width, eave, aspect = 4 / 3 } = {}) {
  const keys = ['wallBottomLeft', 'wallBottomRight', 'eaveRight', 'eaveLeft'];
  if (!keys.every((k) => ok(photo[k])) || !ok(photo.apex)) return null;
  const px = (p) => [p[0] * aspect, p[1]]; // в «квадратные» пиксели
  const [bl, br, er, el, ap] = [...keys.map((k) => px(photo[k])), px(photo.apex)];

  let W = width;
  let E = eave;
  let scaleSource = 'measured';
  if (!(W > 0 && E > 0)) {
    // Нет пары замеров: соотношение сторон стены по фото (почти фронтально) + масштаб по известному размеру или двери.
    const ratio = ((dist(bl, br) + dist(el, er)) / 2) / ((dist(bl, el) + dist(br, er)) / 2); // ширина / высота стены
    if (W > 0) { E = W / ratio; scaleSource = 'photo'; }
    else if (E > 0) { W = E * ratio; scaleSource = 'photo'; }
    else if (ok(photo.doorTop) && ok(photo.doorBottom)) {
      const wallH = (dist(bl, el) + dist(br, er)) / 2;
      E = DOOR_HEIGHT * (wallH / dist(px(photo.doorTop), px(photo.doorBottom)));
      W = E * ratio;
      scaleSource = 'assumption';
    } else {
      // Без масштаба — только уклон (отношение высоты фронтона к полуширине), в предположении фронтального снимка.
      W = ratio; E = 1; scaleSource = 'none';
    }
  }
  // Плоскость стены: x — вдоль стены от левого нижнего угла, y — вверх от земли.
  const H = homography([bl, br, er, el], [[0, 0], [W, 0], [W, E], [0, E]]);
  if (!H) return null;
  const [ax, ay] = apply(H, ap);
  const rise = ay - E;
  if (!(rise > 0) || !(ax > 0) || !(ax < W)) return null;
  const deg = (r) => (Math.atan(r) * 180) / Math.PI;
  const result = {
    // Средний уклон по полуширине; у несимметричного фронтона — оба ската отдельно.
    pitchDeg: round(deg(rise / (W / 2)), 1),
    pitchLeft: round(deg(rise / ax), 1),
    pitchRight: round(deg(rise / (W - ax)), 1),
    symmetric: Math.abs(ax - W / 2) < W * 0.08,
    apexOffset: scaleSource === 'none' ? null : round(ax - W / 2),
    scaleSource,
    frontal: Boolean(photo.frontal),
  };
  if (scaleSource !== 'none') Object.assign(result, { ridgeHeight: round(ay), eaveHeight: round(E), gableWidth: round(W) });
  return result;
}

const median = (list) => {
  const s = list.filter(Number.isFinite).sort((a, b) => a - b);
  if (!s.length) return null;
  return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2;
};

const RANK = { measured: 3, photo: 2, assumption: 1, none: 0 };

/** Сводит ответ ИИ и геометрию в итог: у каждого размера — значение и метка достоверности. */
export function combine(ai, known = {}, aspects = []) {
  const photos = Array.isArray(ai.photos) ? ai.photos : [];
  const geometry = photos.map((p, i) => ({ index: i, ...(gableGeometry(p, { width: known.gableWidth, eave: known.eaveHeight, aspect: aspects[i] || 4 / 3 }) || { skipped: true }) }));
  const good = geometry.filter((g) => !g.skipped);
  const best = good.length ? Math.max(...good.map((g) => RANK[g.scaleSource])) : -1;
  const used = good.filter((g) => RANK[g.scaleSource] === best && (g.frontal || good.every((x) => !x.frontal)));
  const est = ai.estimate || {};
  const value = (name, fromGeometry, aiValue, knownValue) => {
    if (knownValue > 0) return { value: round(knownValue), source: 'measured', note: 'дан замер' };
    if (Number.isFinite(fromGeometry)) {
      const source = best === RANK.measured || best === RANK.photo ? 'photo' : 'assumption';
      return { value: fromGeometry, source, note: best === RANK.assumption ? 'масштаб по двери (≈2,05 м)' : best === RANK.none ? 'только по пропорциям фото' : 'геометрия по фото и замерам' };
    }
    if (aiValue > 0) return { value: round(aiValue), source: 'assumption', note: 'оценка ИИ на глаз' };
    return { value: null, source: 'assumption', note: 'не определено' };
  };
  const g = (key) => (used.length ? round(median(used.map((u) => u[key])), key === 'pitchDeg' ? 1 : 2) : null);
  const pitch = value('pitchDeg', g('pitchDeg'), est.pitchDeg);
  // Уклон — отношение размеров в одной плоскости: масштаб ему не нужен, достаточно фронтального фото.
  if (Number.isFinite(g('pitchDeg')) && best >= RANK.assumption) { pitch.source = 'photo'; pitch.note = 'геометрия фронтона по фото'; }
  else if (Number.isFinite(g('pitchDeg'))) { pitch.source = 'photo'; pitch.note = 'по пропорциям фронтального фото'; }
  return {
    roofType: String(ai.roofType || 'complex'),
    roofTypeRu: String(ai.roofTypeRu || ''),
    typeConfidence: round(Number(ai.typeConfidence) || 0),
    covering: String(ai.covering || ''),
    color: String(ai.color || ''),
    details: (Array.isArray(ai.details) ? ai.details : []).map((d) => ({
      kind: String(d?.kind || 'other'), ru: String(d?.ru || ''), count: Number(d?.count) || 0,
      confidence: round(Number(d?.confidence) || 0), source: d?.seen === false ? 'assumption' : 'photo',
    })),
    pitchDeg: pitch,
    ridgeHeight: value('ridgeHeight', g('ridgeHeight'), est.ridgeHeight, known.ridgeHeight),
    eaveHeight: value('eaveHeight', g('eaveHeight'), est.eaveHeight, known.eaveHeight),
    gableWidth: value('gableWidth', g('gableWidth'), est.gableWidth, known.gableWidth),
    overhang: value('overhang', null, est.overhang),
    floors: Number(est.floors) || null,
    aiEstimate: est,
    geometry,
    hidden: Array.isArray(ai.hidden) ? ai.hidden.map(String) : [],
    advice: String(ai.advice || ''),
  };
}

// ---------- запрос к ИИ ----------

/** Ширина/высота JPEG по маркеру SOF (без сторонних библиотек). */
export function jpegAspect(base64) {
  try {
    const buf = Buffer.from(base64.slice(0, 200_000), 'base64');
    let i = 2;
    while (i < buf.length - 9) {
      if (buf[i] !== 0xff) { i += 1; continue; }
      const marker = buf[i + 1];
      const len = buf.readUInt16BE(i + 2);
      if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
        const h = buf.readUInt16BE(i + 5);
        const w = buf.readUInt16BE(i + 7);
        return w > 0 && h > 0 ? w / h : null;
      }
      i += 2 + len;
    }
  } catch { /* не JPEG */ }
  return null;
}

export async function analyze(body, { meter } = {}) {
  const photos = (Array.isArray(body?.photos) ? body.photos : []).filter((p) => typeof p === 'string' && p.length > 1000).slice(0, 6);
  if (photos.length < 1) throw new ApiError(400, 'Пришлите 3–5 фото дома с разных сторон.');
  if (!config.openrouter?.apiKey) throw new ApiError(503, 'ИИ на сервере не настроен.');
  const num = (v) => (Number.isFinite(Number(v)) && Number(v) > 0 && Number(v) < 100 ? Number(v) : undefined);
  const known = { gableWidth: num(body?.known?.gableWidth), eaveHeight: num(body?.known?.eaveHeight), ridgeHeight: num(body?.known?.ridgeHeight) };
  const knownText = [
    known.gableWidth && `ширина торцевой стены (под фронтоном) ${known.gableWidth} м`,
    known.eaveHeight && `высота от земли до карниза ${known.eaveHeight} м`,
    body?.notes && `заметки: ${String(body.notes).slice(0, 500)}`,
  ].filter(Boolean).join('; ');
  const content = [{ type: 'text', text: `Фото дома: ${photos.length} шт. ${knownText ? `Известно: ${knownText}.` : 'Размеры не даны.'}` }];
  photos.forEach((p, i) => {
    content.push({ type: 'text', text: `Фото ${i + 1}:` });
    content.push({ type: 'image_url', image_url: { url: `data:image/jpeg;base64,${p}` } });
  });
  const payload = {
    model: typeof body?.model === 'string' && body.model.includes('/') ? body.model : MODEL(),
    messages: [{ role: 'system', content: `${SYSTEM}\n\nОтветь ТОЛЬКО одним JSON‑объектом по схеме.` }, { role: 'user', content }],
    max_tokens: 12_000,
    response_format: { type: 'json_object' },
    reasoning: { effort: body?.effort === 'high' ? 'high' : 'medium', exclude: true },
    usage: { include: true },
  };
  // Схема — текстом: строгий json_schema у части маршрутов Gemini режет вложенные массивы.
  payload.messages[0].content += `\nСхема:\n${JSON.stringify(SCHEMA)}`;
  const response = await request(`${config.openrouter.base}/chat/completions`, {
    method: 'POST', headers: { Authorization: `Bearer ${config.openrouter.apiKey}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
  }, 240_000);
  const result = await readJSON(response);
  if (response.status === 402) throw outOfFunds('OpenRouter: на счёте закончились кредиты.');
  if (!response.ok) throw new ApiError(502, `ИИ не ответил (${response.status}): ${result?.error?.message || ''}`.trim(), { retryable: response.status >= 500 });
  const cost = Number(result?.usage?.cost) || 0;
  if (meter) meter.total = (meter.total || 0) + cost;
  const text = result?.choices?.[0]?.message?.content;
  if (!text) throw new ApiError(502, 'ИИ ответил без данных. Попробуйте ещё раз.', { retryable: true });
  const ai = parseLooseJSON(text);
  const out = combine(ai, known, photos.map(jpegAspect));
  console.log(`[roof] ${photos.length} фото, ${out.roofType}, уклон ${out.pitchDeg.value}° (${out.pitchDeg.source}), $${cost.toFixed(4)}`);
  return { ...out, model: result?.model || payload.model, cost: round(cost, 4) };
}
