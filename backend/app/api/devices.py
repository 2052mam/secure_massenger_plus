from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity, get_jwt
from app import db
from app.models.user import User, UserDevice, UserSession
from app.models.audit import AuditLog
from app.services.timestamps import utc_iso
from datetime import datetime

devices_bp = Blueprint('devices', __name__)

def get_client_ip():
    forwarded = request.headers.get('X-Forwarded-For')
    return (forwarded.split(',')[0].strip() if forwarded else request.remote_addr)


def _device_payload(device, sessions, is_current):
    last_session = max(
        sessions, key=lambda s: s.last_used or s.created_at,
    ) if sessions else None
    ip_address = last_session.ip_address if last_session else None
    # The Flutter screen historically read several aliases; keep them all so
    # old and new clients render the same list without showing "-".
    last_active = utc_iso(device.last_active)
    created_at = utc_iso(device.created_at)
    return {
        'id': device.id,
        'device_fingerprint': (device.device_fingerprint or '')[:12] + '...',
        'device_name': device.device_name,
        'device_model': device.device_model,
        'device_type': 'mobile',
        'model': device.device_model,
        'os': device.os_version,
        'os_version': device.os_version,
        'app_version': device.app_version,
        'user_agent': device.user_agent,
        'ip_address': ip_address,
        'is_active': device.is_active,
        'last_active': last_active,
        'last_active_at': last_active,
        'created_at': created_at,
        'is_current': is_current,
        'sessions_count': len(sessions),
    }


@devices_bp.route('/', methods=['GET'])
@devices_bp.route('', methods=['GET'])
@devices_bp.route('/me/devices', methods=['GET'])
@jwt_required()
def list_devices():
    user_id = get_jwt_identity()
    current_device_id = get_jwt().get('device_id')
    devices = UserDevice.query.filter_by(
        user_id=user_id, is_deleted=False,
    ).order_by(UserDevice.last_active.desc()).all()
    # Touch the current row so "last active" is truthful (Telegram-like).
    if current_device_id:
        for device in devices:
            if device.id == current_device_id:
                device.last_active = datetime.utcnow()
                break
        try:
            db.session.commit()
        except Exception:
            db.session.rollback()
    result = []
    for d in devices:
        sessions = UserSession.query.filter_by(
            device_id=d.id, is_active=True,
        ).all()
        result.append(_device_payload(
            d, sessions, d.id == current_device_id,
        ))
    return jsonify({
        'devices': result, 'total': len(result),
        'current_device_id': current_device_id,
    }), 200


@devices_bp.route('/<device_id>/terminate', methods=['POST', 'DELETE'])
@devices_bp.route('/me/devices/<device_id>/terminate', methods=['POST', 'DELETE'])
@jwt_required()
def terminate_device(device_id):
    user_id = get_jwt_identity()
    current_device_id = get_jwt().get('device_id')
    device = UserDevice.query.filter_by(
        id=device_id, user_id=user_id, is_deleted=False,
    ).first()
    if not device:
        return jsonify({'error': 'دستگاه یافت نشد'}), 404
    if device.id == current_device_id:
        return jsonify({
            'error': 'نمی‌توانید نشست فعلی را از همین دستگاه ببندید. برای خروج از گزینه «خروج از حساب» استفاده کنید.',
            'code': 'cannot_terminate_current',
        }), 400
    # Soft delete device and deactivate sessions. The JWT blocklist loader
    # revokes the terminated device's tokens on its very next request, so
    # the remote phone is signed out immediately (Item 4).
    device.is_deleted = True
    device.deleted_at = datetime.utcnow()
    device.deleted_by = user_id
    device.is_active = False
    # Stop push ticks to the removed phone immediately.
    device.push_token = None
    device.push_platform = None
    # deactivate sessions
    UserSession.query.filter_by(
        device_id=device.id, is_active=True,
    ).update({'is_active': False}, synchronize_session=False)
    db.session.add(AuditLog(
        actor_id=user_id, action='terminate_device', entity_type='device',
        entity_id=device_id, ip_address=get_client_ip(),
    ))
    db.session.commit()
    return jsonify({'ok': True, 'message': 'دستگاه حذف شد'}), 200


@devices_bp.route('/terminate-others', methods=['POST'])
@devices_bp.route('/me/devices/terminate-others', methods=['POST'])
@jwt_required()
def terminate_others():
    user_id = get_jwt_identity()
    current_device_id = get_jwt().get('device_id')
    data = request.get_json(silent=True) or {}
    keep_fingerprint = data.get('current_fingerprint')  # legacy clients
    devices = UserDevice.query.filter_by(user_id=user_id, is_deleted=False).all()
    keep_id = current_device_id
    if keep_id is None and keep_fingerprint:
        for d in devices:
            if d.device_fingerprint == keep_fingerprint:
                keep_id = d.id
                break
    if keep_id is None and devices:
        # Oldest tokens carry no device claim; keep the row this request
        # just touched (list_devices updates last_active first).
        devices_sorted = sorted(
            devices, key=lambda x: x.last_active or x.created_at,
            reverse=True,
        )
        keep_id = devices_sorted[0].id
    terminated = 0
    for d in devices:
        if d.id == keep_id:
            continue
        d.is_deleted = True
        d.deleted_at = datetime.utcnow()
        d.deleted_by = user_id
        d.is_active = False
        d.push_token = None
        d.push_platform = None
        UserSession.query.filter_by(
            device_id=d.id, is_active=True,
        ).update({'is_active': False}, synchronize_session=False)
        terminated += 1
    db.session.add(AuditLog(
        actor_id=user_id, action='terminate_other_devices',
        entity_type='user', entity_id=user_id, ip_address=get_client_ip(),
    ))
    db.session.commit()
    return jsonify({'ok': True, 'terminated': terminated}), 200


@devices_bp.route('/sessions', methods=['GET'])
@devices_bp.route('/me/sessions', methods=['GET'])
@jwt_required()
def list_sessions():
    user_id = get_jwt_identity()
    current_device_id = get_jwt().get('device_id')
    sessions = UserSession.query.filter_by(
        user_id=user_id, is_active=True,
    ).order_by(UserSession.last_used.desc()).all()
    result = []
    for s in sessions:
        result.append({
            'id': s.id,
            'device_id': s.device_id,
            'is_current': bool(
                current_device_id and s.device_id == current_device_id),
            'ip_address': s.ip_address,
            'is_active': s.is_active,
            'expires_at': utc_iso(s.expires_at),
            'created_at': utc_iso(s.created_at),
            'last_used': utc_iso(s.last_used),
        })
    return jsonify({'sessions': result, 'total': len(result)}), 200


@devices_bp.route('/sessions/<session_id>/terminate', methods=['POST', 'DELETE'])
@jwt_required()
def terminate_session(session_id):
    """End one session without removing the whole device (Telegram-like)."""
    user_id = get_jwt_identity()
    session = UserSession.query.filter_by(
        id=session_id, user_id=user_id, is_active=True,
    ).first()
    if not session:
        return jsonify({'error': 'نشست یافت نشد'}), 404
    session.is_active = False
    # If this was the device's last live session, its token must not buzz.
    remaining = UserSession.query.filter_by(
        device_id=session.device_id, user_id=user_id, is_active=True,
    ).count()
    if remaining == 0 and session.device_id:
        device = UserDevice.query.filter_by(
            id=session.device_id, user_id=user_id,
        ).first()
        if device:
            device.push_token = None
            device.push_platform = None
    db.session.add(AuditLog(
        actor_id=user_id, action='terminate_session',
        entity_type='session', entity_id=session_id,
        ip_address=get_client_ip(),
    ))
    db.session.commit()
    return jsonify({'ok': True}), 200


@devices_bp.route('/login-history', methods=['GET'])
@devices_bp.route('/me/login-history', methods=['GET'])
@jwt_required()
def login_history():
    user_id = get_jwt_identity()
    # Use AuditLog for login events
    logs = AuditLog.query.filter_by(actor_id=user_id, action='user_login').order_by(AuditLog.created_at.desc()).limit(20).all()
    result = []
    for log in logs:
        result.append({
            'id': log.id,
            'ip_address': log.ip_address,
            'device_fingerprint': log.device_fingerprint,
            'user_agent': log.user_agent,
            'created_at': utc_iso(log.created_at),
        })
    return jsonify({'logins': result}), 200


@devices_bp.route('/notifications', methods=['GET'])
@devices_bp.route('/me/notifications', methods=['GET'])
@jwt_required()
def notifications():
    user_id = get_jwt_identity()
    # Check for recent new device logins (last 7 days) and produce warning
    # Also check if user is limited
    user = User.query.get(user_id)
    notifications = []
    if user and user.is_limited:
        notifications.append({
            'type': 'limited',
            'title': 'حساب محدود شده',
            'message': f'حساب شما به دلیل "{user.limited_reason}" محدود شده تا {user.limited_until.strftime("%Y/%m/%d")} - فقط می‌توانید به چت‌های موجود پاسخ دهید.',
            'severity': 'warning',
        })
    # New device warning: if last login was from new fingerprint within 24h
    from datetime import timedelta
    recent = datetime.utcnow() - timedelta(hours=24)
    recent_logins = AuditLog.query.filter(AuditLog.actor_id==user_id, AuditLog.action=='user_login', AuditLog.created_at >= recent).order_by(AuditLog.created_at.desc()).all()
    # If more than 1 distinct fingerprint in 24h, warn
    fingerprints = set(l.device_fingerprint for l in recent_logins if l.device_fingerprint)
    if len(fingerprints) > 1:
        notifications.append({
            'type': 'new_login',
            'title': 'ورود جدید به حساب',
            'message': f'ورود جدیدی به حساب شما از دستگاهی دیگر شناسایی شد. آیا این شما بودید؟ IP: {recent_logins[0].ip_address if recent_logins else ""}',
            'severity': 'alert',
            'ip_address': recent_logins[0].ip_address if recent_logins else None,
            'created_at': utc_iso(recent_logins[0].created_at) if recent_logins else None,
        })
    # Also check for any new device in last login
    if recent_logins:
        latest = recent_logins[0]
        # Check if its device fingerprint is new (first time seen >1 device)
        total_devices = UserDevice.query.filter_by(user_id=user_id, is_deleted=False).count()
        if total_devices > 1:
            # Add generic login notification if not already added
            if not any(n['type']=='new_login' for n in notifications):
                notifications.append({
                    'type': 'login',
                    'title': 'ورود به حساب',
                    'message': f'وارد حساب شدید از {latest.ip_address or "دستگاه جدید"}',
                    'severity': 'info',
                })
    return jsonify({'notifications': notifications}), 200
