from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.user import User, UserDevice, UserSession
from app.models.audit import AuditLog
from datetime import datetime

devices_bp = Blueprint('devices', __name__)

def get_client_ip():
    return request.headers.get('X-Forwarded-For', request.remote_addr)

@devices_bp.route('/', methods=['GET'])
@devices_bp.route('', methods=['GET'])
@devices_bp.route('/me/devices', methods=['GET'])
@jwt_required()
def list_devices():
    user_id = get_jwt_identity()
    devices = UserDevice.query.filter_by(user_id=user_id, is_deleted=False).order_by(UserDevice.last_active.desc()).all()
    result = []
    for d in devices:
        # also fetch active sessions for device
        sessions = UserSession.query.filter_by(device_id=d.id, is_active=True).all()
        result.append({
            'id': d.id,
            'device_fingerprint': d.device_fingerprint[:12] + '...',
            'device_name': d.device_name,
            'device_model': d.device_model,
            'os_version': d.os_version,
            'app_version': d.app_version,
            'user_agent': d.user_agent,
            'is_active': d.is_active,
            'last_active': d.last_active.isoformat() + 'Z' if d.last_active else None,
            'created_at': d.created_at.isoformat() + 'Z' if d.created_at else None,
            'is_current': False,  # will be determined by fingerprint match if needed
            'sessions_count': len(sessions),
        })
    return jsonify({'devices': result, 'total': len(result)}), 200

@devices_bp.route('/<device_id>/terminate', methods=['POST', 'DELETE'])
@devices_bp.route('/me/devices/<device_id>/terminate', methods=['POST', 'DELETE'])
@jwt_required()
def terminate_device(device_id):
    user_id = get_jwt_identity()
    device = UserDevice.query.filter_by(id=device_id, user_id=user_id, is_deleted=False).first()
    if not device:
        return jsonify({'error': 'دستگاه یافت نشد'}), 404
    # Soft delete device and deactivate sessions
    device.is_deleted = True
    device.deleted_at = datetime.utcnow()
    device.is_active = False
    # deactivate sessions
    UserSession.query.filter_by(device_id=device.id, is_active=True).update({'is_active': False}, synchronize_session=False)
    db.session.add(AuditLog(actor_id=user_id, action='terminate_device', entity_type='device', entity_id=device_id, ip_address=get_client_ip()))
    db.session.commit()
    return jsonify({'ok': True, 'message': 'دستگاه حذف شد'}), 200

@devices_bp.route('/terminate-others', methods=['POST'])
@devices_bp.route('/me/devices/terminate-others', methods=['POST'])
@jwt_required()
def terminate_others():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    keep_fingerprint = data.get('current_fingerprint')  # optional
    # For now terminate all except most recent active
    devices = UserDevice.query.filter_by(user_id=user_id, is_deleted=False).all()
    # keep current device: if fingerprint provided, keep that; else keep most recent
    keep_id = None
    if keep_fingerprint:
        for d in devices:
            if d.device_fingerprint == keep_fingerprint:
                keep_id = d.id
                break
    else:
        # keep most recent
        if devices:
            devices_sorted = sorted(devices, key=lambda x: x.last_active or x.created_at, reverse=True)
            keep_id = devices_sorted[0].id
    terminated = 0
    for d in devices:
        if d.id == keep_id:
            continue
        d.is_deleted = True
        d.deleted_at = datetime.utcnow()
        d.is_active = False
        UserSession.query.filter_by(device_id=d.id, is_active=True).update({'is_active': False}, synchronize_session=False)
        terminated += 1
    db.session.add(AuditLog(actor_id=user_id, action='terminate_other_devices', entity_type='user', entity_id=user_id, ip_address=get_client_ip()))
    db.session.commit()
    return jsonify({'ok': True, 'terminated': terminated}), 200

@devices_bp.route('/sessions', methods=['GET'])
@devices_bp.route('/me/sessions', methods=['GET'])
@jwt_required()
def list_sessions():
    user_id = get_jwt_identity()
    sessions = UserSession.query.filter_by(user_id=user_id, is_active=True).order_by(UserSession.last_used.desc()).all()
    result = []
    for s in sessions:
        result.append({
            'id': s.id,
            'device_id': s.device_id,
            'ip_address': s.ip_address,
            'is_active': s.is_active,
            'expires_at': s.expires_at.isoformat() + 'Z' if s.expires_at else None,
            'created_at': s.created_at.isoformat() + 'Z' if s.created_at else None,
            'last_used': s.last_used.isoformat() + 'Z' if s.last_used else None,
        })
    return jsonify({'sessions': result, 'total': len(result)}), 200

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
            'created_at': log.created_at.isoformat() + 'Z' if log.created_at else None,
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
            'created_at': recent_logins[0].created_at.isoformat() + 'Z' if recent_logins else None,
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
