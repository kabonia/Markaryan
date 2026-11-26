"""PDF аудита СметаПро: обложка, краткая сводка, отчёт аудита и экономика (из .md) — в фирменном стиле.

  /root/projects/markaryan-ios/tools/pdfvenv/bin/python docs/audit/build_pdf.py
"""
from datetime import date
from pathlib import Path

import markdown
from weasyprint import HTML

HERE = Path(__file__).resolve().parent
OUT = HERE / "SmetaPro-Audit-2026-11.pdf"

SUMMARY = """
<h2>Кратко — главное на одной странице</h2>
<table class="kpi">
<tr><td><b>Безопасность и данные</b></td><td>сервер переведён с root на отдельного пользователя; ежедневные резервные копии;
ключи ИИ только на сервере; защита планов от потери при обновлении; лимиты сканов на пользователя.</td></tr>
<tr><td><b>App Store</b></td><td>убрана подсказка оплаты мимо Apple (риск отказа); манифест приватности дополнен.</td></tr>
<tr><td><b>Функции</b></td><td>формулы 14 калькуляторов сверены с нормами — верны; 3D‑обмер больше не занимает
сотни МБ на iPhone; обработчик сканов не падает на реальных сканах; счёт по фото не переполняет память.</td></tr>
<tr><td><b>Интерфейс</b></td><td>кнопка «Пополнить» при нехватке кредитов; без дублей на главной; различимые иконки;
лёгкие анимации; удаление обмеров и комнат долгим нажатием.</td></tr>
<tr><td><b>Экономика</b></td><td>новый прайс: отдельная функция — наценка 230–250 %, пакеты — 170–230 %;
бесплатный ранее 3D‑обмер дома (вместе с крышей по фото) стал платным; учёт стоимости каждого вызова ИИ.</td></tr>
<tr><td><b>Пакеты</b></td><td>6 пакетов под задачи (обмер дома, дизайн комнаты, сметы, ремонт, прораб) от 390 ₽:
покупателю на 11–25 % дешевле, чем по отдельности.</td></tr>
<tr><td><b>Поддержка</b></td><td>в приложении — обращения к менеджеру; менеджер отвечает из Telegram, видит списания
и может вернуть кредиты одной командой.</td></tr>
</table>
<h3>Что нужно от владельца</h3>
<ol>
<li>Отозвать старые ключи Anthropic / OpenAI / BFL в кабинетах сервисов.</li>
<li>Выбрать хранилище для внешней резервной копии (Яндекс Диск, S3…).</li>
<li>В App Store Connect: создать товары (кредиты, подписки, пакеты <code>smetapro.pack.*</code>), отметить в «Конфиденциальности» точную геопозицию и идентификатор пользователя, подать заявку в Small Business Program (15 % вместо 30 %).</li>
<li>Отдельный ключ OpenRouter для разработки; лимит боевого ключа $25/сутки после включения оплаты.</li>
<li>Включить оплату (<code>BILLING_ENABLED=1</code>) после ключей ЮKassa.</li>
</ol>
"""

CSS = """
@page { size: A4; margin: 18mm 16mm 18mm 16mm;
  @bottom-right { content: "СметаПро · аудит · " counter(page) " / " counter(pages); font: 8pt 'DejaVu Sans'; color: #8a8576; } }
@page :first { margin: 0; @bottom-right { content: none; } }
body { font: 9.5pt/1.45 'DejaVu Sans', sans-serif; color: #16241F; }
h1, h2, h3 { font-family: 'DejaVu Serif', serif; color: #0F6B55; }
h1 { font-size: 20pt; margin: 0 0 6pt; page-break-before: always; }
h2 { font-size: 13.5pt; margin: 16pt 0 6pt; border-bottom: 1px solid #E6C888; padding-bottom: 3pt; }
h3 { font-size: 11pt; margin: 12pt 0 4pt; }
table { width: 100%; border-collapse: collapse; margin: 6pt 0 10pt; font-size: 8pt; page-break-inside: auto; }
th { background: #0F6B55; color: #fff; text-align: left; padding: 4pt 5pt; font-weight: 600; }
td { border-bottom: 1px solid #E7E2D6; padding: 3.5pt 5pt; vertical-align: top; }
tr:nth-child(even) td { background: #FBF8F1; }
code { font: 7.8pt 'DejaVu Sans Mono', monospace; background: #F3F0E8; padding: 0 2pt; border-radius: 2pt; }
.cover { height: 297mm; background: linear-gradient(160deg, #116651 0%, #0A4236 60%, #07312A 100%); color: #fff; padding: 60mm 22mm 0; }
.cover .eyebrow { letter-spacing: 3pt; color: #E6C888; font-size: 10pt; }
.cover h1 { color: #fff; font-size: 34pt; page-break-before: avoid; margin: 8pt 0 10pt; }
.cover p { color: #E9EFEA; font-size: 12pt; max-width: 150mm; }
.cover .meta { margin-top: 40mm; color: #E6C888; font-size: 10pt; }
.kpi td:first-child { width: 32mm; color: #0F6B55; }
"""


def md(path: Path) -> str:
    text = path.read_text(encoding="utf8")
    return markdown.markdown(text, extensions=["tables", "fenced_code"])


def main() -> None:
    cover = f"""<section class="cover"><div class="eyebrow">СМЕТАПРО · АУДИТ</div>
<h1>Аудит приложения и экономики</h1>
<p>Безопасность, данные, App Store, функции, интерфейс, себестоимость ИИ, цены, пакеты и маржа.</p>
<p class="meta">Ноябрь 2026 · подготовлено {date.today().strftime('%d.%m.%Y')} · ветки audit-2026-11 и ui-audit-2026-11</p></section>"""
    body = (
        cover
        + "<h1>Сводка</h1>" + SUMMARY
        + md(HERE / "AUDIT-2026-11.md").replace("<h1>", '<h1 style="page-break-before:always">', 1)
        + md(HERE / "ECONOMICS-2026-11.md").replace("<h1>", '<h1 style="page-break-before:always">', 1)
    )
    html = f"<!doctype html><html lang='ru'><head><meta charset='utf-8'><style>{CSS}</style></head><body>{body}</body></html>"
    HTML(string=html).write_pdf(OUT)
    print(OUT, OUT.stat().st_size // 1024, "КБ")


if __name__ == "__main__":
    main()
