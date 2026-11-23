// The payment page (Russia): account number from the app, e‑mail for the receipt, plan or credits, СБП or card → ЮKassa.
import { PRODUCTS } from './billing.js';

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const rub = (n) => `${n.toLocaleString('ru-RU')} ₽`;

const layout = (title, body) => `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title><style>
:root{--bg:#F3F0E8;--card:#FDFCF8;--ink:#16241F;--muted:#66645C;--accent:#0F6B55;--gold:#946F28;--line:rgba(61,51,31,.14)}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
main{max-width:560px;margin:0 auto;padding:32px 16px 48px}h1{font-family:Georgia,"Times New Roman",serif;font-size:30px;margin:6px 0 4px}
.eyebrow{color:var(--gold);font-size:12px;font-weight:600;letter-spacing:.16em;text-transform:uppercase}.muted{color:var(--muted)}
.card{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:18px;margin-top:16px}
label{display:block;font-size:14px;color:var(--muted);margin:14px 0 6px}input{width:100%;font:inherit;padding:13px 14px;border:1px solid var(--line);border-radius:12px;background:#fff;color:var(--ink)}
input:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px rgba(15,107,85,.12)}
.plans{display:grid;gap:10px}.plan{display:flex;justify-content:space-between;gap:12px;align-items:center;border:1px solid var(--line);border-radius:14px;padding:14px;cursor:pointer;background:#fff}
.plan input{width:auto;margin-right:10px}.plan b{font-family:Georgia,serif}.plan small{display:block;color:var(--muted)}
.methods{display:flex;gap:10px}.methods label{flex:1;margin:0;border:1px solid var(--line);border-radius:12px;padding:12px;text-align:center;background:#fff;color:var(--ink);cursor:pointer}
.methods input{display:none}.methods input:checked+span{color:var(--accent);font-weight:600}
button{margin-top:20px;width:100%;border:0;border-radius:14px;padding:16px;font:600 16px/1 inherit;color:#fff;background:linear-gradient(#187C63,#0D5E4B);cursor:pointer}
.err{color:#C73D38;margin-top:12px;min-height:1em}.legal{font-size:12px;color:var(--muted);margin-top:18px}
</style></head><body><main>${body}</main></body></html>`;

export function payPage() {
  const plans = PRODUCTS.map((p, i) => `<label class="plan"><span><input type="radio" name="product" value="${p.id}"${i === 0 ? ' checked' : ''}><b>${esc(p.title)}</b>
<small>${p.plan ? `${p.credits} кредитов${p.id === 'pro_year' ? ' каждый месяц' : ''} · все функции` : 'кредиты не сгорают'}</small></span><b>${rub(p.rub)}</b></label>`).join('');
  return layout('Оплата СметаПро', `<div class="eyebrow">СметаПро</div><h1>Тарифы и кредиты</h1>
<p class="muted">Номер аккаунта — в приложении: Профиль → «Тарифы и баланс». Кредиты появятся в приложении сразу после оплаты.</p>
<form class="card" id="f"><label for="code">Номер аккаунта</label><input id="code" name="code" placeholder="SP-XXXX-XXXX" autocomplete="off" required>
<label for="email">Почта для чека</label><input id="email" name="email" type="email" placeholder="you@mail.ru" required>
<label>Что оплачиваем</label><div class="plans">${plans}</div>
<label>Способ</label><div class="methods"><label><input type="radio" name="method" value="sbp" checked><span>СБП</span></label><label><input type="radio" name="method" value="card"><span>Банковская карта</span></label></div>
<button type="submit">Перейти к оплате</button><div class="err" id="err"></div>
<p class="legal">Оплата через ЮKassa. Подписка продлевается автоматически, отключить можно в приложении. Чек придёт на почту.</p></form>
<script>
const q=new URLSearchParams(location.search);if(q.get('code'))document.getElementById('code').value=q.get('code');
document.getElementById('f').addEventListener('submit',async e=>{e.preventDefault();const d=Object.fromEntries(new FormData(e.target));d.origin=location.origin;
const err=document.getElementById('err');err.textContent='';try{const r=await fetch('/v1/pay/yookassa/create',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d)});
const j=await r.json();if(!r.ok||!j.url)throw new Error(j.error||'Не удалось начать оплату');location.href=j.url}catch(x){err.textContent=x.message}});
</script>`);
}

export function donePage() {
  return layout('Оплата СметаПро', `<div class="eyebrow">СметаПро</div><h1>Спасибо!</h1>
<div class="card"><p>Как только банк подтвердит оплату, кредиты и тариф появятся в приложении — откройте Профиль → «Тарифы и баланс».</p>
<p class="muted">Чек отправлен на почту. Если что‑то пошло не так, напишите нам через помощника в приложении.</p></div>`);
}
