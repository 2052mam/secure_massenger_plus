"""Authentication and phone-verification endpoints.

A mobile number is the primary sign-in identifier for accounts created after
this update.  SMS codes are generated and verified only by the backend; the
Flutter client neither embeds SMS.ir credentials nor receives a raw code.
"""
from __future__ import annotations

from datetime import datetime, timedelta
import hashlib
import hmac
import re
import secrets
import uuid

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import (
    create_access_token,
    create_refresh_token,
    get_jwt_identity,
    jwt_required,
)
from sqlalchemy import func

from app import db
from app.models.audit import AuditLog
from app.models.user import PhoneVerification, User, UserDevice, UserSession
from app.services.sms_ir import SmsDeliveryError, send_verification_code


auth_bp = Blueprint('auth', __name__)

PHONE_CODE_PURPOSE_REGISTER = 'registration'
PHONE_CODE_PURPOSE_LOGIN = 'login'
PHONE_CODE_LENGTH = 6


class AuthFlowError(Exception):
    def __init__(self, message: str, status_code: int = 400, **payload):
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.payload = payload


def _error(error: AuthFlowError):
    return jsonify({'error': error.message, **error.payload}), error.status_code


def get_client_ip() -> str | None:
    # A trusted reverse proxy may append an X-Forwarded-For chain.  The first
    # address is the originating client, and avoids overflowing the DB column.
    forwarded = request.headers.get('X-Forwarded-For')
    return (forwarded.split(',')[0].strip() if forwarded else request.remote_addr)


def _as_device_info(value) -> dict:
    return value if isinstance(value, dict) else {}


def create_device_fingerprint(data: dict) -> str:
    raw = f"{data.get('device_id', '')}-{data.get('model', '')}-{data.get('os', '')}-{data.get('mac', '')}"
    return hashlib.sha256(raw.encode()).hexdigest()


def normalize_mobile_number(value) -> str | None:
    """Normalize common local and international input to E.164.

    SMS.ir is commonly used with Iranian mobile numbers, so the familiar
    ``09xxxxxxxxx`` and ``9xxxxxxxxx`` forms are normalized to ``+98…``. Any
    other valid E.164 mobile number is retained, which keeps the app's account
    model country-code ready if the configured provider supports it.
    """
    if not isinstance(value, str):
        return None
    compact = re.sub(r'[\s()\-.]', '', value)
    if compact.startswith('00'):
        compact = '+' + compact[2:]
    if re.fullmatch(r'09\d{9}', compact):
        compact = '+98' + compact[1:]
    elif re.fullmatch(r'9\d{9}', compact):
        compact = '+98' + compact
    elif re.fullmatch(r'98\d{10}', compact):
        compact = '+' + compact
    if not re.fullmatch(r'\+[1-9]\d{7,14}', compact):
        return None
    return compact


def _mask_mobile(mobile_number: str) -> str:
    if len(mobile_number) <= 6:
        return mobile_number
    return f'{mobile_number[:4]}••••{mobile_number[-3:]}'


def _code_digest(challenge_id: str, code: str) -> str:
    # A plain SHA-256 of a 6-digit code is brute-forceable.  Keying the digest
    # with the server secret means a leaked database cannot validate guesses.
    secret = current_app.config['SECRET_KEY'].encode('utf-8')
    message = f'phone-code:{challenge_id}:{code}'.encode('utf-8')
    return hmac.new(secret, message, hashlib.sha256).hexdigest()


def _new_code() -> str:
    return f'{secrets.randbelow(10 ** PHONE_CODE_LENGTH):0{PHONE_CODE_LENGTH}d}'


def _challenge_or_error(
    challenge_id: object, *, allow_expired: bool = False,
) -> PhoneVerification:
    if not isinstance(challenge_id, str):
        raise AuthFlowError('درخواست تأیید نامعتبر است', 400)
    challenge = db.session.get(PhoneVerification, challenge_id)
    if not challenge or challenge.revoked_at or challenge.consumed_at:
        raise AuthFlowError('کد تأیید نامعتبر یا منقضی شده است', 401)
    if challenge.expires_at <= datetime.utcnow() and not allow_expired:
        raise AuthFlowError('کد تأیید منقضی شده است. دوباره درخواست کنید.', 410)
    return challenge


def _enforce_send_limit(mobile_number: str, purpose: str, ip_address: str | None) -> None:
    now = datetime.utcnow()
    hour_ago = now - timedelta(hours=1)
    recent = PhoneVerification.query.filter(
        PhoneVerification.mobile_number == mobile_number,
        PhoneVerification.created_at >= hour_ago,
    ).order_by(PhoneVerification.created_at.desc()).all()
    # A registration code must not block an immediate *login* request, but a
    # resend cannot be used to flood the same number.
    latest_same_purpose = next((item for item in recent if item.purpose == purpose), None)
    if latest_same_purpose:
        resend_after = int(current_app.config['PHONE_CODE_RESEND_SECONDS'])
        elapsed = (now - latest_same_purpose.created_at).total_seconds()
        if elapsed < resend_after:
            retry_after = max(1, resend_after - int(elapsed))
            raise AuthFlowError(
                'لطفاً پیش از درخواست دوباره کمی صبر کنید.', 429,
                retry_after_seconds=retry_after,
            )
    if len(recent) >= int(current_app.config['PHONE_CODE_MAX_PER_HOUR']):
        raise AuthFlowError('تعداد درخواست کد برای این شماره بیش از حد مجاز است.', 429)

    if ip_address:
        ip_count = PhoneVerification.query.filter(
            PhoneVerification.ip_address == ip_address,
            PhoneVerification.created_at >= hour_ago,
        ).count()
        if ip_count >= int(current_app.config['PHONE_CODE_MAX_PER_IP_HOUR']):
            raise AuthFlowError('تعداد درخواست کد از این اتصال بیش از حد مجاز است.', 429)


def _issue_phone_code(user: User, purpose: str) -> PhoneVerification:
    """Create and deliver exactly one valid challenge for a user/purpose."""
    now = datetime.utcnow()
    ip_address = get_client_ip()
    _enforce_send_limit(user.mobile_number, purpose, ip_address)

    # Only the newest code can be used.  A stale SMS cannot complete a login.
    PhoneVerification.query.filter(
        PhoneVerification.user_id == user.id,
        PhoneVerification.purpose == purpose,
        PhoneVerification.consumed_at.is_(None),
        PhoneVerification.revoked_at.is_(None),
    ).update({PhoneVerification.revoked_at: now}, synchronize_session=False)

    challenge = PhoneVerification(
        id=str(uuid.uuid4()),
        user_id=user.id,
        mobile_number=user.mobile_number,
        purpose=purpose,
        code_hash='',
        expires_at=now + timedelta(seconds=int(current_app.config['PHONE_CODE_TTL_SECONDS'])),
        ip_address=ip_address,
        created_at=now,
    )
    code = _new_code()
    challenge.code_hash = _code_digest(challenge.id, code)
    db.session.add(challenge)
    db.session.flush()

    # Send before committing the challenge. If SMS.ir is unavailable, the
    # transaction rolls back and the user is never left with an unusable code.
    send_verification_code(user.mobile_number, code)
    db.session.add(AuditLog(
        actor_id=user.id,
        action='phone_verification_sent',
        entity_type='phone_verification',
        entity_id=challenge.id,
        ip_address=ip_address,
        user_agent=request.headers.get('User-Agent'),
    ))
    return challenge


def _register_or_update_device(user: User, device_info: dict) -> tuple[UserDevice, bool]:
    """Apply the existing three-account-per-device and device-limit policy."""
    fingerprint = create_device_fingerprint(device_info)
    device = UserDevice.query.filter_by(
        user_id=user.id,
        device_fingerprint=fingerprint,
        is_deleted=False,
    ).first()
    is_new_device = False
    if not device:
        # Preserve the product's original rule: no more than three accounts
        # may use a single stable device fingerprint.
        accounts_on_device = db.session.query(func.count(func.distinct(UserDevice.user_id))).filter(
            UserDevice.device_fingerprint == fingerprint,
            UserDevice.is_deleted == False,
        ).scalar() or 0
        if accounts_on_device >= current_app.config['MAX_ACCOUNTS_PER_DEVICE']:
            raise AuthFlowError(
                'حداکثر ۳ اکانت روی این دستگاه مجاز است. حتی بعد از حذف اپلیکیشن این محدودیت برقرار است.',
                403,
            )
        device_count = UserDevice.query.filter_by(user_id=user.id, is_deleted=False).count()
        if device_count >= current_app.config['MAX_ACCOUNTS_PER_DEVICE']:
            raise AuthFlowError('حداکثر ۳ دستگاه برای این اکانت مجاز است.', 403)
        device = UserDevice(
            user_id=user.id,
            device_fingerprint=fingerprint,
            mac_address=device_info.get('mac_address') or device_info.get('mac'),
            device_name=device_info.get('device_name'),
            device_model=device_info.get('model'),
            os_version=device_info.get('os'),
            app_version=device_info.get('app_version'),
            user_agent=request.headers.get('User-Agent'),
        )
        db.session.add(device)
        is_new_device = True
    elif device.last_active and (
        datetime.utcnow() - device.last_active
    ).total_seconds() > 30 * 24 * 3600:
        is_new_device = True
    device.last_active = datetime.utcnow()
    return device, is_new_device


def _add_new_device_warning(user: User, device: UserDevice, device_info: dict) -> None:
    """Keep the pre-existing saved-messages warning for new-device sign-ins."""
    try:
        from app.models.chat import Chat, ChatMember
        from app.models.message import Message

        member = ChatMember.query.join(Chat).filter(
            ChatMember.user_id == user.id,
            Chat.chat_type == 'saved',
            Chat.is_deleted == False,
            ChatMember.is_deleted == False,
        ).first()
        if not member:
            return
        saved_chat = db.session.get(Chat, member.chat_id)
        if not saved_chat:
            return
        ip_address = get_client_ip() or ''
        device_name = device_info.get('device_name') or device.device_name or 'دستگاه جدید'
        model = device_info.get('model') or device.device_model or ''
        warning = (
            f'⚠️ ورود جدید به حساب شما\n\nدستگاه: {device_name} ({model})\n'
            f'IP: {ip_address}\nزمان: {datetime.utcnow().strftime("%Y/%m/%d %H:%M UTC")}\n\n'
            'اگر این شما نبودید، فوراً رمز عبور خود را تغییر دهید و دستگاه‌های ناشناس را از بخش مدیریت دستگاه‌ها حذف کنید.'
        )
        db.session.add(Message(
            chat_id=saved_chat.id, sender_id=user.id, message_type='text', content=warning,
        ))
        saved_chat.updated_at = datetime.utcnow()
    except Exception:
        # A notification failure must never break a successful authentication.
        current_app.logger.exception('Could not create new-device saved-message warning.')


def _create_authenticated_session(
    user: User,
    device_info: dict,
    *,
    audit_action: str = 'user_login',
) -> dict:
    device, is_new_device = _register_or_update_device(user, device_info)
    user.is_online = True
    user.last_seen = datetime.utcnow()

    access = create_access_token(identity=user.id, expires_delta=timedelta(hours=24))
    refresh = create_refresh_token(identity=user.id, expires_delta=timedelta(days=30))
    db.session.add(UserSession(
        user_id=user.id,
        device_id=device.id,
        refresh_token=refresh,
        ip_address=get_client_ip(),
        expires_at=datetime.utcnow() + timedelta(days=30),
    ))
    db.session.add(AuditLog(
        actor_id=user.id,
        action=audit_action,
        entity_type='user',
        entity_id=user.id,
        ip_address=get_client_ip(),
        user_agent=request.headers.get('User-Agent'),
        device_fingerprint=device.device_fingerprint,
    ))
    if is_new_device:
        _add_new_device_warning(user, device, device_info)

    return {
        'access_token': access,
        'refresh_token': refresh,
        'user': user.to_dict(include_private=True),
        'new_device': is_new_device,
    }


def _verify_challenge_code(challenge: PhoneVerification, code: object) -> None:
    if not isinstance(code, str) or not re.fullmatch(r'\d{6}', code):
        raise AuthFlowError('کد ۶ رقمی نامعتبر است', 401)
    if not hmac.compare_digest(challenge.code_hash, _code_digest(challenge.id, code)):
        challenge.attempts += 1
        if challenge.attempts >= int(current_app.config['PHONE_CODE_MAX_ATTEMPTS']):
            challenge.revoked_at = datetime.utcnow()
            db.session.commit()
            raise AuthFlowError('تعداد تلاش‌های ناموفق بیش از حد مجاز است. کد جدید درخواست کنید.', 429)
        db.session.commit()
        raise AuthFlowError('کد تأیید نادرست است', 401)


@auth_bp.route('/register', methods=['POST'])
def register():
    """Create an inactive account and send the mandatory phone code."""
    data = request.get_json(silent=True) or {}
    email = (data.get('email') or '').strip().lower()
    password = data.get('password') or ''
    username_raw = (data.get('username') or '').strip().lower()
    username = username_raw or None
    display_name = (data.get('display_name') or '').strip()
    mobile_number = normalize_mobile_number(data.get('mobile_number'))
    device_info = _as_device_info(data.get('device_info'))
    try:
        terms_version = int(data.get('terms_version', 0) or 0)
    except (TypeError, ValueError):
        terms_version = 0

    if not email or not password or not display_name or not mobile_number:
        return jsonify({'error': 'نام، ایمیل، رمز عبور و شماره موبایل الزامی هستند'}), 400
    if not re.match(r'^[\w\.-]+@[\w\.-]+\.\w+$', email):
        return jsonify({'error': 'ایمیل نامعتبر است'}), 400
    if len(password) < 8:
        return jsonify({'error': 'رمز عبور باید حداقل ۸ کاراکتر باشد'}), 400
    if username is not None and not re.match(r'^[a-z0-9_]{3,30}$', username):
        return jsonify({'error': 'نام کاربری فقط حروف کوچک، عدد و _ (۳ تا ۳۰ کاراکتر)'}), 400

    existing_email = User.query.filter_by(email=email, is_deleted=False).first()
    existing_mobile = User.query.filter_by(mobile_number=mobile_number, is_deleted=False).first()
    if existing_email and existing_email.is_active:
        return jsonify({'error': 'این ایمیل قبلاً ثبت شده'}), 409
    if existing_mobile and existing_mobile.is_active and existing_mobile.id != (existing_email.id if existing_email else None):
        return jsonify({'error': 'این شماره موبایل قبلاً ثبت شده'}), 409
    if existing_email and existing_mobile and existing_email.id != existing_mobile.id:
        return jsonify({'error': 'ایمیل یا شماره موبایل در انتظار تأیید دیگری است'}), 409

    existing_username = None
    if username is not None:
        existing_username = User.query.filter_by(username=username, is_deleted=False).first()
        if existing_username and existing_username.is_active and existing_username.id != (existing_email.id if existing_email else None):
            return jsonify({'error': 'این نام کاربری قبلاً گرفته شده'}), 409
        if existing_username and existing_email and existing_username.id != existing_email.id:
            return jsonify({'error': 'این نام کاربری در انتظار تأیید دیگری است'}), 409

    terms_accepted = bool(data.get('terms_accepted'))
    user = existing_email or existing_mobile
    if user is None:
        user = User(
            email=email,
            mobile_number=mobile_number,
            username=username,
            display_name=display_name,
            is_active=False,
            is_2fa_enabled=False,
            terms_version=(terms_version or 1) if terms_accepted else 0,
            terms_accepted_at=datetime.utcnow() if terms_accepted else None,
        )
        user.set_password(password)
        user.generate_totp_secret()
        db.session.add(user)
    else:
        # An unverified registration has no usable session. Restarting it with
        # the same email/mobile is safe and avoids orphaned pending accounts.
        user.email = email
        user.mobile_number = mobile_number
        user.username = username
        user.display_name = display_name
        user.mobile_verified_at = None
        user.is_active = False
        user.is_2fa_enabled = False
        user.terms_version = (terms_version or 1) if terms_accepted else 0
        user.terms_accepted_at = datetime.utcnow() if terms_accepted else None
        user.set_password(password)
        user.generate_totp_secret()

    try:
        db.session.flush()
        challenge = _issue_phone_code(user, PHONE_CODE_PURPOSE_REGISTER)
        db.session.add(AuditLog(
            actor_id=user.id,
            action='user_register',
            entity_type='user',
            entity_id=user.id,
            ip_address=get_client_ip(),
            user_agent=request.headers.get('User-Agent'),
            device_fingerprint=create_device_fingerprint(device_info),
        ))
        db.session.commit()
    except AuthFlowError as error:
        db.session.rollback()
        return _error(error)
    except SmsDeliveryError:
        db.session.rollback()
        current_app.logger.warning('Could not deliver registration verification SMS.')
        return jsonify({'error': 'ارسال پیامک تأیید موقتاً ممکن نیست. دوباره تلاش کنید.'}), 503
    except Exception:
        db.session.rollback()
        current_app.logger.exception('Could not start phone registration.')
        return jsonify({'error': 'ثبت‌نام موقتاً ممکن نیست. دوباره تلاش کنید.'}), 503

    return jsonify({
        'message': 'کد تأیید به شماره موبایل شما ارسال شد.',
        'verification_id': challenge.id,
        'mobile_number': _mask_mobile(mobile_number),
        'expires_in_seconds': int(current_app.config['PHONE_CODE_TTL_SECONDS']),
    }), 201


@auth_bp.route('/request-phone-code', methods=['POST'])
def request_phone_code():
    """Start a phone-primary login without exposing whether a number exists."""
    data = request.get_json(silent=True) or {}
    mobile_number = normalize_mobile_number(data.get('mobile_number'))
    if not mobile_number:
        return jsonify({'error': 'شماره موبایل نامعتبر است'}), 400

    user = User.query.filter_by(
        mobile_number=mobile_number,
        is_deleted=False,
        is_active=True,
    ).first()
    # Always return the same accepted response for an unknown number. This
    # avoids turning the endpoint into an account-enumeration oracle.
    if not user or not user.mobile_verified_at:
        return jsonify({
            'message': 'اگر این شماره ثبت شده باشد، کد تأیید ارسال می‌شود.',
            'verification_id': str(uuid.uuid4()),
            'mobile_number': _mask_mobile(mobile_number),
            'expires_in_seconds': int(current_app.config['PHONE_CODE_TTL_SECONDS']),
        }), 202

    try:
        challenge = _issue_phone_code(user, PHONE_CODE_PURPOSE_LOGIN)
        db.session.commit()
    except AuthFlowError as error:
        db.session.rollback()
        return _error(error)
    except SmsDeliveryError:
        db.session.rollback()
        current_app.logger.warning('Could not deliver login verification SMS.')
        # Do not disclose a valid account through a provider delivery failure.
        return jsonify({'error': 'ارسال پیامک تأیید موقتاً ممکن نیست. دوباره تلاش کنید.'}), 503

    return jsonify({
        'message': 'اگر این شماره ثبت شده باشد، کد تأیید ارسال می‌شود.',
        'verification_id': challenge.id,
        'mobile_number': _mask_mobile(mobile_number),
        'expires_in_seconds': int(current_app.config['PHONE_CODE_TTL_SECONDS']),
    }), 202


@auth_bp.route('/resend-phone-code', methods=['POST'])
def resend_phone_code():
    data = request.get_json(silent=True) or {}
    try:
        old = _challenge_or_error(data.get('verification_id'), allow_expired=True)
        if old.verified_at:
            raise AuthFlowError('این درخواست قبلاً تأیید شده است.', 409)
        user = User.query.filter_by(id=old.user_id, is_deleted=False).first()
        if not user or (old.purpose == PHONE_CODE_PURPOSE_LOGIN and not user.is_active):
            raise AuthFlowError('کد تأیید نامعتبر یا منقضی شده است', 401)
        challenge = _issue_phone_code(user, old.purpose)
        db.session.commit()
    except AuthFlowError as error:
        db.session.rollback()
        return _error(error)
    except SmsDeliveryError:
        db.session.rollback()
        current_app.logger.warning('Could not resend phone verification SMS.')
        return jsonify({'error': 'ارسال پیامک تأیید موقتاً ممکن نیست. دوباره تلاش کنید.'}), 503

    return jsonify({
        'message': 'کد جدید ارسال شد.',
        'verification_id': challenge.id,
        'mobile_number': _mask_mobile(challenge.mobile_number),
        'expires_in_seconds': int(current_app.config['PHONE_CODE_TTL_SECONDS']),
    }), 202


@auth_bp.route('/verify-phone', methods=['POST'])
def verify_phone():
    """Validate an SMS code and either authenticate or request optional TOTP."""
    data = request.get_json(silent=True) or {}
    try:
        challenge = _challenge_or_error(data.get('verification_id'))
        _verify_challenge_code(challenge, data.get('code'))
        user = User.query.filter_by(id=challenge.user_id, is_deleted=False).first()
        if not user:
            raise AuthFlowError('کد تأیید نامعتبر یا منقضی شده است', 401)

        if challenge.purpose == PHONE_CODE_PURPOSE_REGISTER:
            user.is_active = True
            user.mobile_verified_at = datetime.utcnow()
            challenge.verified_at = datetime.utcnow()
            challenge.consumed_at = datetime.utcnow()
            db.session.add(AuditLog(
                actor_id=user.id,
                action='phone_registration_verified',
                entity_type='user',
                entity_id=user.id,
                ip_address=get_client_ip(),
            ))
            response = _create_authenticated_session(
                user, _as_device_info(data.get('device_info')), audit_action='user_register_login',
            )
            db.session.commit()
            return jsonify(response), 200

        if challenge.purpose != PHONE_CODE_PURPOSE_LOGIN or not user.is_active:
            raise AuthFlowError('کد تأیید نامعتبر یا منقضی شده است', 401)

        challenge.verified_at = datetime.utcnow()
        if user.is_2fa_enabled:
            db.session.commit()
            return jsonify({
                'require_2fa': True,
                'verification_id': challenge.id,
                'message': 'کد Google Authenticator را وارد کنید.',
            }), 200

        challenge.consumed_at = datetime.utcnow()
        response = _create_authenticated_session(
            user, _as_device_info(data.get('device_info')), audit_action='phone_login',
        )
        db.session.commit()
        return jsonify(response), 200
    except AuthFlowError as error:
        # Invalid-code attempts are committed inside _verify_challenge_code.
        # Rollback here is harmless for unchanged transactions and prevents a
        # partial session/device record from leaking after another failure.
        db.session.rollback()
        return _error(error)
    except Exception:
        db.session.rollback()
        current_app.logger.exception('Could not verify phone code.')
        return jsonify({'error': 'تأیید کد موقتاً ممکن نیست. دوباره تلاش کنید.'}), 503


@auth_bp.route('/verify-login-2fa', methods=['POST'])
def verify_login_2fa():
    """Finish an SMS-verified login for an account with optional TOTP enabled."""
    data = request.get_json(silent=True) or {}
    try:
        challenge = _challenge_or_error(data.get('verification_id'))
        if (
            challenge.purpose != PHONE_CODE_PURPOSE_LOGIN
            or not challenge.verified_at
            or not challenge.user_id
        ):
            raise AuthFlowError('درخواست تأیید نامعتبر است', 401)
        user = User.query.filter_by(id=challenge.user_id, is_deleted=False, is_active=True).first()
        if not user or not user.is_2fa_enabled:
            raise AuthFlowError('درخواست تأیید نامعتبر است', 401)
        code = data.get('code')
        if not isinstance(code, str) or not re.fullmatch(r'\d{6}', code) or not user.verify_totp(code):
            challenge.attempts += 1
            if challenge.attempts >= int(current_app.config['PHONE_CODE_MAX_ATTEMPTS']):
                challenge.revoked_at = datetime.utcnow()
                db.session.commit()
                raise AuthFlowError('تعداد تلاش‌های ناموفق بیش از حد مجاز است. کد جدید درخواست کنید.', 429)
            db.session.commit()
            raise AuthFlowError('کد Google Authenticator نادرست است', 401)
        challenge.consumed_at = datetime.utcnow()
        response = _create_authenticated_session(
            user, _as_device_info(data.get('device_info')), audit_action='phone_login_2fa',
        )
        db.session.commit()
        return jsonify(response), 200
    except AuthFlowError as error:
        db.session.rollback()
        return _error(error)
    except Exception:
        db.session.rollback()
        current_app.logger.exception('Could not complete two-factor phone login.')
        return jsonify({'error': 'تأیید کد موقتاً ممکن نیست. دوباره تلاش کنید.'}), 503


# ---------------------------------------------------------------------------
# Legacy password login: retained so people who registered before phone auth
# can still access and migrate naturally. New phone-verified accounts use the
# phone endpoints above and never need this path.
# ---------------------------------------------------------------------------
@auth_bp.route('/login', methods=['POST'])
def login():
    data = request.get_json(silent=True) or {}
    email = (data.get('email') or '').strip().lower()
    password = data.get('password') or ''
    code = data.get('totp_code')
    device_info = _as_device_info(data.get('device_info'))

    user = User.query.filter_by(email=email, is_deleted=False).first()
    if not user or not user.check_password(password):
        return jsonify({'error': 'ایمیل یا رمز عبور اشتباه است'}), 401
    if not user.is_active:
        return jsonify({'error': 'اکانت غیرفعال است'}), 403
    if user.mobile_number and user.mobile_verified_at:
        return jsonify({
            'error': 'برای ورود، شماره موبایل و کد پیامک را وارد کنید.',
            'require_phone': True,
        }), 400
    if user.is_2fa_enabled:
        if not code:
            return jsonify({'error': 'کد 2FA الزامی است', 'require_2fa': True}), 401
        if not user.verify_totp(code):
            return jsonify({'error': 'کد 2FA نامعتبر است'}), 401

    try:
        response = _create_authenticated_session(user, device_info)
        db.session.commit()
        return jsonify(response), 200
    except AuthFlowError as error:
        db.session.rollback()
        return _error(error)


@auth_bp.route('/verify-2fa', methods=['POST'])
def verify_2fa_register():
    """Compatibility endpoint for an incomplete registration from old clients."""
    data = request.get_json(silent=True) or {}
    user_id = data.get('user_id')
    code = data.get('code')
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    if user.mobile_number:
        return jsonify({'error': 'این نسخه از ثبت‌نام با شماره موبایل تأیید می‌شود.'}), 409
    if not user.verify_totp(code):
        return jsonify({'error': 'کد 2FA نامعتبر است'}), 401
    try:
        response = _create_authenticated_session(user, _as_device_info(data.get('device_info')))
        db.session.commit()
        return jsonify(response), 200
    except AuthFlowError as error:
        db.session.rollback()
        return _error(error)


@auth_bp.route('/2fa/setup', methods=['POST'])
@jwt_required()
def setup_two_factor():
    """Return a newly generated secret only to an already authenticated owner."""
    user = User.query.filter_by(id=get_jwt_identity(), is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    if user.is_2fa_enabled:
        return jsonify({'error': 'تأیید دو مرحله‌ای از قبل فعال است.'}), 409
    secret = user.generate_totp_secret()
    db.session.add(AuditLog(
        actor_id=user.id,
        action='two_factor_setup_started',
        entity_type='user',
        entity_id=user.id,
        ip_address=get_client_ip(),
    ))
    db.session.commit()
    return jsonify({
        'totp_secret': secret,
        'totp_uri': user.get_totp_uri(),
        'warning': 'کلید را در Google Authenticator ذخیره کنید. تا وارد کردن کد، فعال نمی‌شود.',
    }), 200


@auth_bp.route('/2fa/enable', methods=['POST'])
@jwt_required()
def enable_two_factor():
    data = request.get_json(silent=True) or {}
    user = User.query.filter_by(id=get_jwt_identity(), is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    if user.is_2fa_enabled:
        return jsonify({'error': 'تأیید دو مرحله‌ای از قبل فعال است.'}), 409
    if not user.verify_totp(data.get('code')):
        return jsonify({'error': 'کد Google Authenticator نامعتبر است'}), 401
    user.is_2fa_enabled = True
    db.session.add(AuditLog(
        actor_id=user.id,
        action='two_factor_enabled',
        entity_type='user',
        entity_id=user.id,
        ip_address=get_client_ip(),
    ))
    db.session.commit()
    return jsonify({'message': 'تأیید دو مرحله‌ای فعال شد.', 'user': user.to_dict(include_private=True)}), 200


@auth_bp.route('/2fa/disable', methods=['POST'])
@jwt_required()
def disable_two_factor():
    data = request.get_json(silent=True) or {}
    user = User.query.filter_by(id=get_jwt_identity(), is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    if not user.is_2fa_enabled:
        return jsonify({'error': 'تأیید دو مرحله‌ای فعال نیست.'}), 409
    if not user.verify_totp(data.get('code')):
        return jsonify({'error': 'کد Google Authenticator نامعتبر است'}), 401
    user.is_2fa_enabled = False
    # Rotate the stored secret so an old authenticator code cannot be reused if
    # the owner re-enables the feature later.
    user.generate_totp_secret()
    db.session.add(AuditLog(
        actor_id=user.id,
        action='two_factor_disabled',
        entity_type='user',
        entity_id=user.id,
        ip_address=get_client_ip(),
    ))
    db.session.commit()
    return jsonify({'message': 'تأیید دو مرحله‌ای غیرفعال شد.', 'user': user.to_dict(include_private=True)}), 200


@auth_bp.route('/logout', methods=['POST'])
@jwt_required()
def logout():
    user_id = get_jwt_identity()
    user = db.session.get(User, user_id)
    if user:
        user.is_online = False
        user.last_seen = datetime.utcnow()
        db.session.commit()
    return jsonify({'message': 'خروج موفق'}), 200


@auth_bp.route('/refresh', methods=['POST'])
@jwt_required(refresh=True)
def refresh():
    user_id = get_jwt_identity()
    access = create_access_token(identity=user_id, expires_delta=timedelta(hours=24))
    return jsonify({'access_token': access}), 200
