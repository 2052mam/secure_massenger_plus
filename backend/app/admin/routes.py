from flask import Blueprint, render_template_string, current_app, request, redirect, session
from functools import wraps
from app import db
from app.models.user import User, UserDevice
from app.models.chat import Chat
from app.models.message import Message
from app.models.audit import AuditLog
from app.models.media import MediaFile
import os

admin_web_bp = Blueprint('admin_web', __name__)

def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('admin_logged_in'):
            return redirect(f"/{current_app.config['ADMIN_SECRET_PATH']}/login")
        return f(*args, **kwargs)
    return decorated

BASE_CSS = """
:root{--bg:#0b1220;--card:#121a2b;--line:#1e2a44;--text:#e8eefc;--muted:#8b9bb8;--accent:#3b82f6;--ok:#22c55e;--danger:#ef4444}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Tahoma,Segoe UI,sans-serif;background:var(--bg);color:var(--text);min-height:100vh}
a{color:var(--accent);text-decoration:none}
.header{background:linear-gradient(90deg,#0f172a,#1e293b);padding:14px 24px;display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid var(--line);position:sticky;top:0;z-index:20}
.header h1{font-size:1.15rem;color:#93c5fd}
.nav a{color:var(--muted);margin-right:16px;font-size:.92rem}
.nav a:hover,.nav a.active{color:#fff}
.container{max-width:1280px;margin:20px auto;padding:0 16px}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin-bottom:18px}
.stat{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px;text-align:center}
.stat-value{font-size:1.7rem;font-weight:700;color:#60a5fa}
.stat-label{color:var(--muted);font-size:.82rem;margin-top:4px}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px;margin-bottom:16px;overflow:auto}
h2{font-size:1.05rem;margin-bottom:12px;color:#93c5fd}
table{width:100%;border-collapse:collapse;font-size:.88rem}
th,td{padding:10px 8px;text-align:right;border-bottom:1px solid var(--line)}
th{color:var(--muted);font-weight:600;background:#0d1526}
tr:hover{background:#0d1526}
.badge{display:inline-block;padding:2px 8px;border-radius:999px;font-size:.75rem}
.badge-ok{background:#14532d;color:#86efac}
.badge-off{background:#1e293b;color:#94a3b8}
.badge-bad{background:#7f1d1d;color:#fca5a5}
.btn{background:var(--accent);color:#fff;border:none;padding:7px 12px;border-radius:8px;cursor:pointer;font-size:.8rem}
.btn-danger{background:var(--danger)}
.btn-sm{padding:4px 8px;font-size:.75rem}
input,button{font-family:inherit}
.login-wrap{min-height:100vh;display:flex;align-items:center;justify-content:center}
.login-card{width:100%;max-width:380px;background:var(--card);border:1px solid var(--line);border-radius:16px;padding:28px}
.login-card h2{margin-bottom:14px}
.login-card input{width:100%;padding:12px;margin:8px 0;border-radius:10px;border:1px solid var(--line);background:#0b1220;color:#fff}
.login-card button{width:100%;margin-top:10px;padding:12px;border:none;border-radius:10px;background:var(--accent);color:#fff;cursor:pointer;font-size:1rem}
.error{color:#fca5a5;margin-top:8px}
"""

@admin_web_bp.route('/<path:secret_path>/login', methods=['GET', 'POST'])
def admin_login(secret_path):
    if secret_path != current_app.config['ADMIN_SECRET_PATH']:
        return "Not Found", 404
    error = None
    if request.method == 'POST':
        if request.form.get('username') == os.getenv('ADMIN_USERNAME') and request.form.get('password') == os.getenv('ADMIN_PASSWORD'):
            session['admin_logged_in'] = True
            return redirect(f"/{secret_path}/")
        error = 'نام کاربری یا رمز اشتباه است'
    return render_template_string(f"""
<!DOCTYPE html><html lang="fa" dir="rtl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Admin Login</title><style>{BASE_CSS}</style></head><body>
<div class="login-wrap"><div class="login-card">
<h2>🔒 ورود ادمین SecureMessenger</h2>
<form method="post">
<input name="username" placeholder="نام کاربری" required>
<input name="password" type="password" placeholder="رمز عبور" required>
<button type="submit">ورود به پنل</button>
{"<p class='error'>"+error+"</p>" if error else ""}
</form></div></div></body></html>
""")

@admin_web_bp.route('/<path:secret_path>/logout')
def admin_logout(secret_path):
    session.pop('admin_logged_in', None)
    return redirect(f"/{secret_path}/login")

@admin_web_bp.route('/<path:secret_path>/')
@admin_required
def admin_dashboard(secret_path):
    if secret_path != current_app.config['ADMIN_SECRET_PATH']:
        return "Not Found", 404
    stats = {
        'users': User.query.filter_by(is_deleted=False).count(),
        'online': User.query.filter_by(is_deleted=False, is_online=True).count(),
        'chats': Chat.query.filter_by(is_deleted=False).count(),
        'messages': Message.query.filter_by(is_deleted_for_all=False).count(),
        'devices': UserDevice.query.filter_by(is_deleted=False).count(),
        'media': MediaFile.query.filter_by(is_deleted=False).count(),
    }
    recent_users = User.query.filter_by(is_deleted=False).order_by(User.created_at.desc()).limit(12).all()
    recent_audit = AuditLog.query.order_by(AuditLog.created_at.desc()).limit(15).all()
    rows_u = "".join([
        f"<tr><td>{u.display_name}</td><td>{u.email}</td><td>@{u.username}</td>"
        f"<td>{'<span class=badge badge-ok>آنلاین</span>' if u.is_online else '<span class=badge badge-off>آفلاین</span>'}"
        f"{'' if u.is_active else ' <span class=badge badge-bad>غیرفعال</span>'}</td>"
        f"<td>{u.created_at.strftime('%Y-%m-%d %H:%M') if u.created_at else '-'}</td>"
        f"<td><form method=post action='/{secret_path}/users/{u.id}/toggle' style='display:inline'>"
        f"<button class='btn btn-sm {'btn-danger' if u.is_active else ''}' type=submit>{'غیرفعال' if u.is_active else 'فعال'}</button></form></td></tr>"
        for u in recent_users
    ])
    rows_a = "".join([
        f"<tr><td>{a.action}</td><td>{a.entity_type}</td><td>{(a.entity_id or '-')[:10]}</td>"
        f"<td>{a.ip_address or '-'}</td><td>{a.created_at.strftime('%Y-%m-%d %H:%M:%S') if a.created_at else '-'}</td></tr>"
        for a in recent_audit
    ])
    return render_template_string(f"""
<!DOCTYPE html><html lang="fa" dir="rtl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Admin Dashboard</title><style>{BASE_CSS}</style></head><body>
<div class="header"><h1>🔒 SecureMessenger Admin</h1>
<div class="nav">
<a class="active" href="/{secret_path}/">داشبورد</a>
<a href="/{secret_path}/users">کاربران</a>
<a href="/{secret_path}/chats">چت‌ها</a>
<a href="/{secret_path}/messages">پیام‌ها</a>
<a href="/{secret_path}/audit">لاگ امنیتی</a>
<a href="/{secret_path}/logout">خروج</a>
</div></div>
<div class="container">
<div class="stats">
<div class="stat"><div class="stat-value">{stats['users']}</div><div class="stat-label">کاربران</div></div>
<div class="stat"><div class="stat-value">{stats['online']}</div><div class="stat-label">آنلاین</div></div>
<div class="stat"><div class="stat-value">{stats['chats']}</div><div class="stat-label">چت‌ها</div></div>
<div class="stat"><div class="stat-value">{stats['messages']}</div><div class="stat-label">پیام‌ها</div></div>
<div class="stat"><div class="stat-value">{stats['devices']}</div><div class="stat-label">دستگاه‌ها</div></div>
<div class="stat"><div class="stat-value">{stats['media']}</div><div class="stat-label">مدیا</div></div>
</div>
<div class="card"><h2>آخرین کاربران</h2>
<table><thead><tr><th>نام</th><th>ایمیل</th><th>یوزرنیم</th><th>وضعیت</th><th>تاریخ</th><th>عملیات</th></tr></thead>
<tbody>{rows_u}</tbody></table></div>
<div class="card"><h2>لاگ امنیتی اخیر</h2>
<table><thead><tr><th>عملیات</th><th>نوع</th><th>شناسه</th><th>IP</th><th>زمان</th></tr></thead>
<tbody>{rows_a}</tbody></table></div>
</div></body></html>
""")

@admin_web_bp.route('/<path:secret_path>/users/<user_id>/toggle', methods=['POST'])
@admin_required
def toggle_user(secret_path, user_id):
    if secret_path != current_app.config['ADMIN_SECRET_PATH']:
        return "Not Found", 404
    user = User.query.get(user_id)
    if user:
        user.is_active = not user.is_active
        db.session.add(AuditLog(actor_id='admin', action='admin_toggle_user', entity_type='user', entity_id=user_id, new_value=str(user.is_active)))
        db.session.commit()
    return redirect(f"/{secret_path}/")

def _list_page(secret_path, title, headers, rows):
    head = "".join(f"<th>{h}</th>" for h in headers)
    return f"""<!DOCTYPE html><html lang="fa" dir="rtl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title><style>{BASE_CSS}</style></head><body>
<div class="header"><h1>🔒 Admin</h1><div class="nav">
<a href="/{secret_path}/">داشبورد</a><a href="/{secret_path}/users">کاربران</a>
<a href="/{secret_path}/chats">چت‌ها</a><a href="/{secret_path}/messages">پیام‌ها</a>
<a href="/{secret_path}/audit">لاگ</a><a href="/{secret_path}/logout">خروج</a>
</div></div>
<div class="container"><div class="card"><h2>{title}</h2>
<table><thead><tr>{head}</tr></thead><tbody>{rows}</tbody></table>
</div></div></body></html>"""

@admin_web_bp.route('/<path:secret_path>/users')
@admin_required
def admin_users(secret_path):
    if secret_path != current_app.config['ADMIN_SECRET_PATH']:
        return "Not Found", 404
    users = User.query.filter_by(is_deleted=False).order_by(User.created_at.desc()).limit(200).all()
    rows = "".join([
        f"<tr><td>{u.display_name}</td><td>{u.email}</td><td>@{u.username}</td>"
        f"<td>{'آنلاین' if u.is_online else 'آفلاین'}</td><td>{'فعال' if u.is_active else 'غیرفعال'}</td>"
        f"<td>{u.created_at.strftime('%Y-%m-%d') if u.created_at else '-'}</td></tr>"
        for u in users
    ])
    return _list_page(secret_path, "کاربران", ["نام","ایمیل","یوزرنیم","وضعیت","فعال","تاریخ"], rows)

@admin_web_bp.route('/<path:secret_path>/chats')
@admin_required
def admin_chats(secret_path):
    if secret_path != current_app.config['ADMIN_SECRET_PATH']:
        return "Not Found", 404
    chats = Chat.query.filter_by(is_deleted=False).order_by(Chat.updated_at.desc()).limit(200).all()
    rows = "".join([
        f"<tr><td>{c.id[:8]}…</td><td>{c.chat_type}</td><td>{c.title or '-'}</td><td>{c.username or '-'}</td>"
        f"<td>{c.updated_at.strftime('%Y-%m-%d %H:%M') if c.updated_at else '-'}</td></tr>"
        for c in chats
    ])
    return _list_page(secret_path, "چت‌ها", ["ID","نوع","عنوان","یوزرنیم","به‌روزرسانی"], rows)

@admin_web_bp.route('/<path:secret_path>/messages')
@admin_required
def admin_messages(secret_path):
    if secret_path != current_app.config['ADMIN_SECRET_PATH']:
        return "Not Found", 404
    msgs = Message.query.order_by(Message.created_at.desc()).limit(200).all()
    rows = "".join([
        f"<tr><td>{m.id[:8]}…</td><td>{m.message_type}</td><td>{(m.content or '')[:50]}</td>"
        f"<td>{m.sender_id[:8]}…</td><td>{'حذف‌شده' if m.is_deleted_for_all else 'فعال'}</td>"
        f"<td>{m.created_at.strftime('%Y-%m-%d %H:%M') if m.created_at else '-'}</td></tr>"
        for m in msgs
    ])
    return _list_page(secret_path, "پیام‌ها", ["ID","نوع","محتوا","فرستنده","وضعیت","زمان"], rows)

@admin_web_bp.route('/<path:secret_path>/audit')
@admin_required
def admin_audit(secret_path):
    if secret_path != current_app.config['ADMIN_SECRET_PATH']:
        return "Not Found", 404
    logs = AuditLog.query.order_by(AuditLog.created_at.desc()).limit(300).all()
    rows = "".join([
        f"<tr><td>{a.action}</td><td>{a.entity_type}</td><td>{(a.entity_id or '-')[:12]}</td>"
        f"<td>{a.ip_address or '-'}</td><td>{a.created_at.strftime('%Y-%m-%d %H:%M:%S') if a.created_at else '-'}</td></tr>"
        for a in logs
    ])
    return _list_page(secret_path, "لاگ امنیتی", ["عملیات","نوع","شناسه","IP","زمان"], rows)
