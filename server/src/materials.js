// «Свой материал»: the client sends a photo or a file of a product or a material (tile, facade panel, toilet, sink, wallpaper…).
// The AI says what it is, asks where it goes and how (placement and laying method), and gives English wording for the render.
import * as ai from './ai.js';
import { ApiError, languageNote } from './util.js';

const SCHEMA = {
  type: 'object',
  properties: {
    category: { type: 'string', description: 'tile | floor | wall | facade | roof | sanitary | furniture | lighting | door | window | textile | decor | appliance | other' },
    title: { type: 'string', description: 'по-русски, как в магазине: тип, размер, цвет, фактура, бренд/коллекция если видно' },
    english: { type: 'string', description: 'precise English description for an image model: type, colour, pattern, texture, finish, size/format, shape, style' },
    question: { type: 'string', description: 'короткий вопрос клиенту по-русски: куда и как это поставить' },
    placements: { type: 'array', items: { type: 'object', properties: { ru: { type: 'string' }, en: { type: 'string' } } } },
    methods: { type: 'array', items: { type: 'object', properties: { ru: { type: 'string' }, en: { type: 'string' } } } },
  },
};

const SYSTEM = `Ты — дизайнер интерьеров и экстерьеров и прораб. Клиент прислал фото или файл товара или материала, который хочет видеть в визуализации.
1. Определи, что это (плитка, керамогранит, мозаика, фасадная панель, кирпич, штукатурка, кровля, ламинат, паркет, обои, краска, унитаз, раковина, ванна, смеситель, душевая, мебель, светильник, дверь, окно, текстиль, декор, техника…), с размером/форматом, цветом, фактурой, отделкой; бренд и коллекцию — только если видны.
2. english — точное описание для модели изображений, чтобы она воспроизвела именно этот предмет.
3. placements — 3–6 вариантов, КУДА это поставить, с учётом типа помещения (например для плитки: пол, стены целиком, фартук, душевая зона, одна акцентная стена; для унитаза: на место существующего, у стены справа…). Первый — самый вероятный.
4. methods — 2–6 вариантов, КАК (для плитки — раскладка: прямая, со смещением 1/2, 1/3, ёлочка, диагональ, вертикально/горизонтально, цвет шва; для фасада — направление панелей; для сантехники — подвесной/напольный монтаж, инсталляция; для обоев — на все стены/акцент). Если способ не нужен — один вариант «как на фото».
5. question — один короткий вопрос клиенту.
Если на изображении не материал и не предмет интерьера — category other и вопрос, что это и куда.`;

export async function identify(body) {
  const context = [body.screen && `Экран: ${String(body.screen).slice(0, 80)}`, body.room && `Помещение: ${String(body.room).slice(0, 80)}`].filter(Boolean).join('. ');
  const result = await ai.json({
    system: SYSTEM + languageNote(body.language),
    messages: [{ role: 'user', text: `${context || 'Помещение не указано.'}${body.fileName ? `\nФайл: ${String(body.fileName).slice(0, 120)}` : ''}${body.text ? `\nТекст из файла: ${String(body.text).slice(0, 4000)}` : ''}`, image: body.image }],
    schema: SCHEMA, name: 'material', maxTokens: 3000, model: 'anthropic/claude-sonnet-5.5',
  });
  const options = (list) => (Array.isArray(list) ? list : []).map((o) => ({ ru: String(o?.ru || '').slice(0, 80), en: String(o?.en || '').slice(0, 160) })).filter((o) => o.ru && o.en).slice(0, 6);
  const placements = options(result.placements);
  if (!result.title || !placements.length) throw new ApiError(502, 'ИИ не распознал материал. Попробуйте другое фото.', { retryable: true });
  return {
    category: String(result.category || 'other').slice(0, 20), title: String(result.title).slice(0, 160), english: String(result.english || '').slice(0, 600),
    question: String(result.question || 'Куда это поставить и как?').slice(0, 200), placements, methods: options(result.methods),
  };
}
