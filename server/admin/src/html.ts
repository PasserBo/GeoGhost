import type { LogRow, QueueRow, ReportRow, Stats } from './db';

/** Everything user-written (nicknames, report notes, places) goes through this. */
export function esc(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] as string);
}

const SLA_HOURS = 24;

export function waited(since: string | null, now = Date.now()): { text: string; late: boolean } {
  if (!since) return { text: '—', late: false };
  const hours = (now - Date.parse(since)) / 3_600_000;
  const text = hours < 1 ? `${Math.max(1, Math.round(hours * 60))} 分钟` : hours < 48 ? `${Math.floor(hours)} 小时` : `${Math.floor(hours / 24)} 天`;
  return { text, late: hours >= SLA_HOURS };
}

const KIND: Record<string, string> = { sticker: '贴纸', graffiti: '涂鸦', mural: '壁画', poster: '海报', tag: 'Tag', other: '其他' };
const ACTION: Record<string, string> = { approve: '通过', reject: '拒绝', remove: '删除', ban: '封禁', unban: '解除封禁' };
const STATUS: Record<string, string> = { pending: '审核中', public: '已公开', hidden: '已隐藏', removed: '已删除', uploading: '上传中' };

export type Tab = 'pending' | 'reported' | 'log';

export function page(opts: { tab: Tab; stats: Stats; actor: string; body: string; flash?: string | null; now?: number }): string {
  const { tab, stats, actor, body, flash } = opts;
  const p = waited(stats.oldest_pending_at, opts.now), r = waited(stats.oldest_report_at, opts.now);
  const tabLink = (t: Tab, label: string) =>
    `<a class="tab${t === tab ? ' on' : ''}" href="/?tab=${t}">${label}</a>`;
  return `<!doctype html><html lang="zh-Hans"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>GeoGhost 审核</title>
<script src="/vendor/libheif.js" defer></script><script src="/admin.js" defer></script>
<style>
body{font:15px/1.45 -apple-system,system-ui,sans-serif;margin:0;background:#f4f0e8;color:#1f1b16}
header{position:sticky;top:0;background:#f4f0e8;padding:12px 14px 0;border-bottom:1px solid #ddd5c8;z-index:1}
h1{font-size:18px;margin:0 0 8px}.who{float:right;font-size:12px;color:#7a7066}
.stats{display:flex;gap:10px;margin-bottom:10px}.stat{flex:1;background:#fffaf2;border-radius:12px;padding:8px 10px}
.stat b{font-size:22px;display:block}.late{color:#c62828;font-weight:600}
.tab{display:inline-block;padding:8px 12px;color:#7a7066;text-decoration:none}.tab.on{color:#ff6b2c;border-bottom:2px solid #ff6b2c}
main{padding:12px 14px 40px;max-width:760px;margin:auto}
.card{background:#fffaf2;border-radius:16px;padding:12px;margin-bottom:12px;display:flex;gap:12px;flex-wrap:wrap}
.noheic{width:160px;height:160px;display:flex;align-items:center;padding:10px;box-sizing:border-box;font-size:12px;color:#c62828;background:#fdecea;border-radius:10px}
.overlay{position:fixed;inset:0;background:rgba(0,0,0,.8);color:#fff;display:flex;align-items:center;justify-content:center;z-index:9;cursor:zoom-out}
.overlay img{max-width:95vw;max-height:95vh;background:repeating-conic-gradient(#e8e2d8 0 25%,#fff 0 50%) 0 0/16px 16px}
.card img{width:160px;height:160px;object-fit:contain;background:repeating-conic-gradient(#e8e2d8 0 25%,#fff 0 50%) 0 0/16px 16px;border-radius:10px}
.meta{flex:1;min-width:200px}.meta div{margin:2px 0}.muted{color:#7a7066;font-size:13px}
.actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px}.actions form{margin:0}
button{font:inherit;border:0;border-radius:10px;padding:8px 14px;cursor:pointer}
.ok{background:#2e7d32;color:#fff}.no{background:#ef6c00;color:#fff}.del{background:#c62828;color:#fff}.plain{background:#e8e2d8}
.flash{background:#e8f5e9;border-radius:10px;padding:8px 12px;margin-bottom:12px}
.reports{margin:6px 0 0;padding-left:18px}.empty{text-align:center;color:#7a7066;padding:40px 0}
table{width:100%;border-collapse:collapse;font-size:13px}td{padding:6px 4px;border-bottom:1px solid #e8e2d8;vertical-align:top}
</style></head><body>
<header><span class="who">${esc(actor)}</span><h1>GeoGhost 审核</h1>
<div class="stats">
<div class="stat"><b>${stats.pending_count}</b>待审核 · 最久 <span class="${p.late ? 'late' : ''}">${esc(p.text)}</span></div>
<div class="stat"><b>${stats.reported_count}</b>被举报 · 最久 <span class="${r.late ? 'late' : ''}">${esc(r.text)}</span></div>
</div>
${tabLink('pending', '待审核')}${tabLink('reported', '被举报')}${tabLink('log', '操作记录')}
</header><main>${flash ? `<div class="flash">${esc(flash)}</div>` : ''}${body}</main></body></html>`;
}

function actionButton(tab: Tab, action: string, label: string, cls: string, fields: Record<string, string>, confirmText?: string): string {
  const hidden = Object.entries(fields).map(([k, v]) => `<input type="hidden" name="${esc(k)}" value="${esc(v)}">`).join('');
  const confirm = confirmText ? ` data-confirm="${esc(confirmText)}"` : '';
  return `<form method="post" action="/action"${confirm}><input type="hidden" name="action" value="${esc(action)}">` +
    `<input type="hidden" name="tab" value="${tab}">${hidden}<button class="${cls}">${label}</button></form>`;
}

export function queue(tab: 'pending' | 'reported', rows: QueueRow[], reports: Map<string, ReportRow[]>, now = Date.now()): string {
  if (rows.length === 0) return `<p class="empty">${tab === 'pending' ? '没有待审核的帖子' : '没有未处理的举报'}</p>`;
  return rows.map((row) => {
    const w = waited(tab === 'pending' ? row.created_at : row.first_report_at, now);
    const place = [row.locality, row.country_code].filter(Boolean).join(', ') || '未知区域';
    const list = (reports.get(row.id) ?? []).filter((r) => !r.resolved_at)
      .map((r) => `<li>${esc(r.reason)}${r.note ? ` — ${esc(r.note)}` : ''} <span class="muted">${esc(waited(r.created_at, now).text)}前</span></li>`).join('');
    const post = { post_id: row.id };
    const user = { user_id: row.author_id };
    return `<div class="card"><a href="/img/${esc(row.image_key)}" data-heic-full><img data-heic="/img/${esc(row.thumb_key)}" alt=""></a>
<div class="meta">
<div><b>${esc(row.author_nickname ?? '（无昵称）')}</b>${row.author_banned ? ' <span class="late">已封禁</span>' : ''}
 <span class="muted">通过 ${row.author_approved} · 被隐藏 ${row.author_hidden}</span></div>
<div>${esc(KIND[row.post_kind] ?? row.post_kind)} · ${esc(place)} · ${esc(row.captured_on ?? '')}</div>
<div class="muted">${esc(STATUS[row.status] ?? row.status)} · 已等待 <span class="${w.late ? 'late' : ''}">${esc(w.text)}</span></div>
${tab === 'reported' ? `<div>${row.open_reports} 人举报</div><ul class="reports">${list}</ul>` : ''}
<div class="actions">
${row.status !== 'public' ? actionButton(tab, 'approve', '通过', 'ok', post) : actionButton(tab, 'approve', '保留（关闭举报）', 'ok', post)}
${row.status !== 'hidden' ? actionButton(tab, 'reject', '拒绝', 'no', post) : ''}
${actionButton(tab, 'remove', '删除', 'del', post, '删除这张帖子和它的图片？无法撤销。')}
${row.author_banned ? actionButton(tab, 'unban', '解除封禁', 'plain', user) : actionButton(tab, 'ban', '封禁发布者', 'plain', user, '封禁这个发布者？他的所有帖子将对其他人不可见。')}
</div></div></div>`;
  }).join('');
}

export function log(rows: LogRow[]): string {
  if (rows.length === 0) return '<p class="empty">还没有操作记录</p>';
  return `<table>${rows.map((r) => `<tr><td>${esc(new Date(r.at).toISOString().replace('T', ' ').slice(0, 16))}</td>
<td>${esc(ACTION[r.action] ?? r.action)}</td><td class="muted">${esc(r.actor)}</td>
<td class="muted">${r.post_id ? `帖子 ${esc(r.post_id.slice(0, 8))}` : ''}${r.user_id ? ` 用户 ${esc(r.user_id.slice(0, 8))}` : ''}${r.note ? ` — ${esc(r.note)}` : ''}</td></tr>`).join('')}</table>`;
}

export function message(status: number, text: string): string {
  return `<!doctype html><html lang="zh-Hans"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>GeoGhost 审核</title></head><body style="font:16px system-ui;padding:40px;text-align:center"><h1>${status}</h1><p>${esc(text)}</p></body></html>`;
}
