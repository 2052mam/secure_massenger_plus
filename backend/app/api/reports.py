from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.user import User
from app.models.chat import Chat, ChatMember
from app.models.message import Message
from app.models.report import Report
from app.models.audit import AuditLog
from datetime import datetime, timedelta

reports_bp = Blueprint('reports', __name__)

VALID_REASONS = {'spam', 'violence', 'child_abuse', 'pornography', 'fake_account', 'copyright', 'illegal_drugs', 'personal_data', 'harassment', 'other'}
VALID_TARGET_TYPES = {'user', 'group', 'channel', 'message'}

def get_client_ip():
    return request.headers.get('X-Forwarded-For', request.remote_addr)

def is_admin(user_id):
    u = User.query.filter_by(id=user_id, is_deleted=False).first()
    return u and u.is_admin

def user_in_chat(user_id, chat_id):
    from app.models.chat import ChatMember, Chat
    return db.session.query(ChatMember.id).join(Chat).filter(
        ChatMember.chat_id == chat_id,
        ChatMember.user_id == user_id,
        ChatMember.is_deleted.is_(False),
        Chat.is_deleted.is_(False),
        Chat.is_deleted_for_all.is_(False),
    ).first() is not None

@reports_bp.route('/user', methods=['POST'])
@jwt_required()
def report_user():
    reporter_id = get_jwt_identity()
    data = request.get_json() or {}
    target_user_id = data.get('target_user_id') or data.get('user_id')
    reason = (data.get('reason') or '').strip().lower()
    description = (data.get('description') or '').strip()[:1000]
    message_id = data.get('message_id')

    if not target_user_id or not reason:
        return jsonify({'error': 'target_user_id و reason الزامی است'}), 400
    if reason not in VALID_REASONS:
        return jsonify({'error': f'reason باید یکی از {VALID_REASONS} باشد'}), 400
    if target_user_id == reporter_id:
        return jsonify({'error': 'نمی‌توانید خود را ریپورت کنید'}), 400
    target = User.query.filter_by(id=target_user_id, is_deleted=False).first()
    if not target:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    # optional message validation
    target_message_id = None
    if message_id:
        msg = Message.query.filter_by(id=message_id, sender_id=target_user_id, is_deleted=False).first()
        if msg:
            target_message_id = msg.id
        else:
            # allow report without strict message link
            pass

    # Telegram logic: prevent spam reports - limit 5 reports per day per reporter
    today = datetime.utcnow() - timedelta(hours=24)
    recent = Report.query.filter(Report.reporter_id == reporter_id, Report.created_at >= today).count()
    if recent >= 10:
        return jsonify({'error': 'حد گزارش روزانه پر شده است'}), 429

    report = Report(
        reporter_id=reporter_id,
        target_type='user',
        target_user_id=target_user_id,
        target_message_id=target_message_id,
        reason=reason,
        description=description,
    )
    db.session.add(report)
    db.session.add(AuditLog(actor_id=reporter_id, action='report_user', entity_type='user', entity_id=target_user_id, ip_address=get_client_ip()))
    db.session.commit()
    return jsonify(report.to_dict()), 201

@reports_bp.route('/chat', methods=['POST'])
@jwt_required()
def report_chat():
    reporter_id = get_jwt_identity()
    data = request.get_json() or {}
    target_chat_id = data.get('target_chat_id') or data.get('chat_id')
    reason = (data.get('reason') or '').strip().lower()
    description = (data.get('description') or '').strip()[:1000]
    if not target_chat_id or not reason:
        return jsonify({'error': 'target_chat_id و reason الزامی است'}), 400
    if reason not in VALID_REASONS:
        return jsonify({'error': 'reason نامعتبر است'}), 400
    chat = Chat.query.filter_by(id=target_chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    if chat.chat_type not in ('group', 'channel'):
        return jsonify({'error': 'فقط گروه و کانال قابل ریپورت هستند'}), 400
    # user must be member or have seen it via invite? allow any authenticated user to report public groups
    # but private groups require membership
    if not chat.is_public and not user_in_chat(reporter_id, target_chat_id):
        # allow reporter even if not member if they have a message forwarded? For now require membership for private
        return jsonify({'error': 'برای گزارش گروه خصوصی باید عضو باشید'}), 403

    report = Report(
        reporter_id=reporter_id,
        target_type=chat.chat_type,
        target_chat_id=target_chat_id,
        reason=reason,
        description=description,
    )
    db.session.add(report)
    db.session.add(AuditLog(actor_id=reporter_id, action='report_chat', entity_type='chat', entity_id=target_chat_id, ip_address=get_client_ip()))
    db.session.commit()
    return jsonify(report.to_dict()), 201

@reports_bp.route('/message', methods=['POST'])
@jwt_required()
def report_message():
    reporter_id = get_jwt_identity()
    data = request.get_json() or {}
    target_message_id = data.get('message_id') or data.get('target_message_id')
    reason = (data.get('reason') or '').strip().lower()
    description = (data.get('description') or '').strip()[:1000]
    if not target_message_id or not reason:
        return jsonify({'error': 'message_id و reason الزامی است'}), 400
    if reason not in VALID_REASONS:
        return jsonify({'error': 'reason نامعتبر است'}), 400
    msg = Message.query.filter_by(id=target_message_id, is_deleted=False).first()
    if not msg:
        return jsonify({'error': 'پیام یافت نشد'}), 404
    # reporter must be in same chat to see message
    if not user_in_chat(reporter_id, msg.chat_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403
    # determine target type: if message in group/channel, target_type is group/channel, else user
    chat = db.session.get(Chat, msg.chat_id)
    target_type = 'message'
    target_chat_id = msg.chat_id if chat and chat.chat_type in ('group','channel') else None
    target_user_id = msg.sender_id if chat and chat.chat_type == 'private' else None
    report = Report(
        reporter_id=reporter_id,
        target_type=target_type,
        target_chat_id=target_chat_id,
        target_user_id=target_user_id,
        target_message_id=target_message_id,
        reason=reason,
        description=description,
    )
    db.session.add(report)
    db.session.add(AuditLog(actor_id=reporter_id, action='report_message', entity_type='message', entity_id=target_message_id, ip_address=get_client_ip()))
    db.session.commit()
    return jsonify(report.to_dict()), 201

@reports_bp.route('/', methods=['GET'])
@jwt_required()
def list_reports():
    user_id = get_jwt_identity()
    if not is_admin(user_id):
        return jsonify({'error': 'دسترسی ادمین ندارید'}), 403
    status = request.args.get('status')
    target_type = request.args.get('target_type')
    page = int(request.args.get('page', 1))
    per_page = min(int(request.args.get('per_page', 50)), 100)
    query = Report.query
    if status:
        query = query.filter(Report.status == status)
    if target_type:
        query = query.filter(Report.target_type == target_type)
    pagination = query.order_by(Report.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    return jsonify({
        'reports': [r.to_dict(include_reporter=True) for r in pagination.items],
        'total': pagination.total,
        'page': page,
        'pages': pagination.pages,
    }), 200

@reports_bp.route('/my', methods=['GET'])
@jwt_required()
def my_reports():
    user_id = get_jwt_identity()
    reports = Report.query.filter_by(reporter_id=user_id).order_by(Report.created_at.desc()).limit(50).all()
    return jsonify({'reports': [r.to_dict() for r in reports]}), 200

@reports_bp.route('/<report_id>/resolve', methods=['POST'])
@jwt_required()
def resolve_report(report_id):
    admin_id = get_jwt_identity()
    if not is_admin(admin_id):
        return jsonify({'error': 'دسترسی ادمین ندارید'}), 403
    report = Report.query.filter_by(id=report_id).first()
    if not report:
        return jsonify({'error': 'گزارش یافت نشد'}), 404
    if report.status != 'pending':
        return jsonify({'error': 'این گزارش قبلاً بررسی شده'}), 400
    data = request.get_json() or {}
    action = (data.get('action') or '').strip().lower()
    admin_note = (data.get('admin_note') or data.get('reason') or '').strip()[:1000]
    # valid actions depend on target_type
    # user: dismiss, warn, limit, ban
    # group/channel: dismiss, warn, suspend, delete, close
    # message: dismiss, delete_message, ban_user etc.
    valid_actions = {'dismiss', 'warn', 'limit_user', 'ban_user', 'unban_user', 'suspend_chat', 'delete_chat', 'close_chat', 'reopen_chat', 'delete_message'}
    if action not in valid_actions:
        return jsonify({'error': f'action باید یکی از {valid_actions} باشد'}), 400

    now = datetime.utcnow()
    result_msg = ''

    if action == 'dismiss':
        report.status = 'dismissed'
        report.admin_note = admin_note or 'بدون اقدام'
        result_msg = 'گزارش رد شد'
    elif action == 'warn':
        report.status = 'reviewed'
        report.admin_note = admin_note or 'هشدار ارسال شد'
        result_msg = 'هشدار ثبت شد'
    elif action in ('limit_user', 'ban_user', 'unban_user'):
        if not report.target_user_id:
            return jsonify({'error': 'این گزارش هدف کاربری ندارد'}), 400
        user = User.query.filter_by(id=report.target_user_id).first()
        if not user:
            return jsonify({'error': 'کاربر یافت نشد'}), 404
        if action == 'limit_user':
            # Telegram limited: can only chat with existing contacts, cannot start new chats
            user.is_limited = True
            # limit for 7 days by default, or duration provided
            days = int(data.get('days', 7))
            user.limited_until = now + timedelta(days=days)
            user.limited_reason = admin_note or 'نقض قوانین (اسپم/مزاحمت)'
            user.limited_by = admin_id
            report.status = 'action_taken'
            report.admin_note = f'کاربر محدود شد تا {user.limited_until.isoformat()} - {user.limited_reason}'
            result_msg = f'کاربر محدود شد ({days} روز)'
            # Notify user via saved messages: create system message
            try:
                from app.models.chat import ChatMember
                # find or create saved chat for limited user to notify
                saved = Chat.query.filter_by(chat_type='saved', created_by=user.id, is_deleted=False).first()
                if not saved:
                    # find saved via membership
                    member_saved = ChatMember.query.join(Chat).filter(ChatMember.user_id==user.id, Chat.chat_type=='saved', Chat.is_deleted==False, ChatMember.is_deleted==False).first()
                    if member_saved:
                        saved = db.session.get(Chat, member_saved.chat_id)
                if saved:
                    sys_msg = Message(chat_id=saved.id, sender_id=admin_id, message_type='text',
                                      content=f'⚠️ حساب شما به دلیل "{user.limited_reason}" محدود شد. تا {user.limited_until.strftime("%Y/%m/%d")} فقط می‌توانید به افرادی که قبلاً با شما چت کرده‌اند پاسخ دهید و نمی‌توانید چت جدید آغاز کنید. مانند تلگرام، محدودیت پس از بررسی برداشته خواهد شد.')
                    db.session.add(sys_msg)
            except Exception:
                pass
        elif action == 'ban_user':
            user.is_active = False
            report.status = 'action_taken'
            report.admin_note = admin_note or 'حساب غیرفعال شد'
            result_msg = 'کاربر مسدود شد'
        elif action == 'unban_user':
            user.is_active = True
            user.is_limited = False
            user.limited_until = None
            user.limited_reason = None
            report.status = 'action_taken'
            report.admin_note = admin_note or 'محدودیت برداشته شد'
            result_msg = 'محدودیت کاربر برداشته شد'
    elif action in ('suspend_chat', 'delete_chat', 'close_chat', 'reopen_chat'):
        if not report.target_chat_id:
            return jsonify({'error': 'این گزارش هدف چتی ندارد'}), 400
        chat = db.session.get(Chat, report.target_chat_id)
        if not chat:
            return jsonify({'error': 'چت یافت نشد'}), 404
        if action == 'suspend_chat':
            chat.is_suspended = True
            chat.suspension_reason = admin_note or 'محتوای نامناسب گزارش شده'
            chat.suspended_at = now
            chat.suspended_by = admin_id
            report.status = 'action_taken'
            report.admin_note = f'گروه/کانال تعلیق شد: {chat.suspension_reason}'
            result_msg = 'گروه/کانال تعلیق شد'
            # notify owner via system message in that chat
            try:
                owner_msg = Message(chat_id=chat.id, sender_id=admin_id, message_type='text',
                                    content=f'🚫 این {"کانال" if chat.chat_type=="channel" else "گروه"} توسط مدیریت به دلیل "{chat.suspension_reason}" تعلیق شد. پس از بررسی مجدد فعال خواهد شد.')
                db.session.add(owner_msg)
            except Exception:
                pass
        elif action == 'delete_chat':
            chat.is_deleted = True
            chat.is_deleted_for_all = True
            chat.deleted_at = now
            chat.deleted_by = admin_id
            # soft delete members
            ChatMember.query.filter_by(chat_id=chat.id).update({'is_deleted': True, 'deleted_at': now, 'deleted_by': admin_id}, synchronize_session=False)
            report.status = 'action_taken'
            report.admin_note = admin_note or 'گروه/کانال حذف شد'
            result_msg = 'گروه/کانال حذف شد'
        elif action == 'close_chat':
            chat.is_closed = True
            chat.closed_reason = admin_note or 'بسته شدن توسط مدیریت'
            chat.closed_at = now
            report.status = 'action_taken'
            report.admin_note = f'گروه/کانال بسته شد: {chat.closed_reason}'
            result_msg = 'گروه/کانال بسته شد'
            try:
                sys_msg = Message(chat_id=chat.id, sender_id=admin_id, message_type='text',
                                  content=f'🔒 این {"کانال" if chat.chat_type=="channel" else "گروه"} بسته شد. دلیل: {chat.closed_reason}')
                db.session.add(sys_msg)
            except Exception:
                pass
        elif action == 'reopen_chat':
            chat.is_suspended = False
            chat.suspension_reason = None
            chat.suspended_at = None
            chat.is_closed = False
            chat.closed_reason = None
            chat.closed_at = None
            chat.is_deleted = False
            chat.is_deleted_for_all = False
            report.status = 'action_taken'
            report.admin_note = admin_note or 'بازگشایی شد'
            result_msg = 'گروه/کانال بازگشایی شد'
    elif action == 'delete_message':
        if not report.target_message_id:
            return jsonify({'error': 'پیام برای حذف یافت نشد'}), 400
        msg = db.session.get(Message, report.target_message_id)
        if msg:
            msg.is_deleted = True
            msg.is_deleted_for_all = True
            msg.deleted_at = now
            msg.deleted_by = admin_id
        report.status = 'action_taken'
        report.admin_note = admin_note or 'پیام حذف شد'
        result_msg = 'پیام حذف شد'

    report.resolved_by = admin_id
    report.resolved_at = now
    if not report.admin_note:
        report.admin_note = admin_note
    db.session.add(AuditLog(actor_id=admin_id, action=f'report_{action}', entity_type='report', entity_id=report.id, ip_address=get_client_ip()))
    db.session.commit()
    return jsonify({'message': result_msg, 'report': report.to_dict()}), 200

@reports_bp.route('/<report_id>', methods=['GET'])
@jwt_required()
def get_report(report_id):
    user_id = get_jwt_identity()
    report = Report.query.filter_by(id=report_id).first()
    if not report:
        return jsonify({'error': 'گزارش یافت نشد'}), 404
    # only reporter or admin can view
    if report.reporter_id != user_id and not is_admin(user_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403
    return jsonify(report.to_dict(include_reporter=True)), 200
