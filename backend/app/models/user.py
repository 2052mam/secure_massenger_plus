from app.services.timestamps import utc_iso
from app import db
from datetime import datetime, timedelta
from werkzeug.security import generate_password_hash, check_password_hash
import pyotp
import uuid

class User(db.Model):
    __tablename__ = 'users'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    email = db.Column(db.String(255), unique=True, nullable=False, index=True)
    # E.164 is stored at rest (for example, +989121234567). It is private and
    # used as the primary sign-in identifier after it has been verified.
    mobile_number = db.Column(db.String(16), unique=True, nullable=True, index=True)
    mobile_verified_at = db.Column(db.DateTime, nullable=True)
    password_hash = db.Column(db.String(255), nullable=False)
    # Telegram-like: username (@id) is OPTIONAL. NULL means the user has no
    # public id. Unique only when set (NULLs never collide in MySQL/SQLite).
    username = db.Column(db.String(50), unique=True, nullable=True, index=True)
    display_name = db.Column(db.String(100), nullable=False)
    bio = db.Column(db.Text, nullable=True)
    avatar_url = db.Column(db.String(500), nullable=True)

    # Google Authenticator is optional. A secret is pre-generated for schema
    # compatibility; it is only exposed when the owner explicitly enables 2FA.
    totp_secret = db.Column(db.String(32), nullable=False)
    is_2fa_enabled = db.Column(
        db.Boolean, default=False, nullable=False, server_default=db.false()
    )

    # Privacy
    is_online = db.Column(db.Boolean, default=False)
    last_seen = db.Column(db.DateTime, default=datetime.utcnow)
    show_last_seen = db.Column(db.Boolean, default=True)  # Ghost mode = False
    show_profile_photo = db.Column(db.Boolean, default=True)
    show_bio = db.Column(db.Boolean, default=True)

    allow_group_adds = db.Column(db.Boolean, nullable=False, default=True, server_default=db.true())

    # Telegram-like: block forwarding of my messages (privacy).
    allow_forwarding = db.Column(db.Boolean, nullable=False, default=True, server_default=db.true())

    # Rules / Terms acceptance (shown during registration + settings).
    terms_version = db.Column(db.Integer, nullable=False, default=0, server_default='0')
    terms_accepted_at = db.Column(db.DateTime, nullable=True)

    # Optional 4 digit lock for the archived chats folder (hashed, never stored raw)
    archive_pin_hash = db.Column(db.String(255), nullable=True)
    archive_pin_updated_at = db.Column(db.DateTime, nullable=True)

    # Status
    is_active = db.Column(db.Boolean, default=True)
    is_admin = db.Column(db.Boolean, default=False)
    is_support = db.Column(db.Boolean, default=False)

    # Telegram-like restriction after reports (limited account)
    is_limited = db.Column(db.Boolean, default=False, nullable=False)
    limited_until = db.Column(db.DateTime, nullable=True)
    limited_reason = db.Column(db.Text, nullable=True)
    limited_by = db.Column(db.String(36), nullable=True)

    # Soft Delete
    is_deleted = db.Column(db.Boolean, default=False, index=True)
    deleted_at = db.Column(db.DateTime, nullable=True)
    deleted_by = db.Column(db.String(36), nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    devices = db.relationship('UserDevice', backref='user', lazy='dynamic')
    sessions = db.relationship('UserSession', backref='user', lazy='dynamic')

    def set_password(self, password: str):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password: str) -> bool:
        return check_password_hash(self.password_hash, password)

    def generate_totp_secret(self):
        self.totp_secret = pyotp.random_base32()
        return self.totp_secret

    def get_totp_uri(self):
        return pyotp.totp.TOTP(self.totp_secret).provisioning_uri(
            name=self.email, issuer_name='SecureMessenger'
        )

    def verify_totp(self, code: str) -> bool:
        if not self.totp_secret or not isinstance(code, str):
            return False
        totp = pyotp.TOTP(self.totp_secret)
        return totp.verify(code, valid_window=2)  # ±60s for device clock drift

    # ----- Archive lock (4 digit PIN) -------------------------------------
    def set_archive_pin(self, pin: str):
        """Store only a hash; the PIN itself can never be read back."""
        self.archive_pin_hash = generate_password_hash(pin)
        self.archive_pin_updated_at = datetime.utcnow()

    def clear_archive_pin(self):
        self.archive_pin_hash = None
        self.archive_pin_updated_at = datetime.utcnow()

    def check_archive_pin(self, pin: str) -> bool:
        if not self.archive_pin_hash:
            return True
        if not isinstance(pin, str):
            return False
        return check_password_hash(self.archive_pin_hash, pin)

    @property
    def has_archive_pin(self) -> bool:
        return bool(self.archive_pin_hash)

    def to_dict(self, include_private=False):
        # A killed/offline app cannot send a final offline request. Expire its
        # heartbeat instead of leaving the profile online indefinitely.
        online = bool(self.is_online and self.last_seen and
                      timedelta(0) <= datetime.utcnow() - self.last_seen < timedelta(seconds=60))
        data = {
            'id': self.id,
            'username': self.username,
            'display_name': self.display_name,
            'bio': self.bio if self.show_bio else None,
            'avatar_url': self.avatar_url if self.show_profile_photo else None,
            'is_online': online if self.show_last_seen else False,
            'last_seen': utc_iso(self.last_seen) if self.show_last_seen and self.last_seen else None,
            'created_at': utc_iso(self.created_at),
        }
        if include_private:
            data.update({
                'email': self.email,
                'mobile_number': self.mobile_number,
                'mobile_verified_at': utc_iso(self.mobile_verified_at) if self.mobile_verified_at else None,
                'avatar_url': self.avatar_url,
                'bio': self.bio,
                'allow_group_adds': self.allow_group_adds,
                'allow_forwarding': bool(self.allow_forwarding) if self.allow_forwarding is not None else True,
                'terms_version': self.terms_version or 0,
                'terms_accepted_at': utc_iso(self.terms_accepted_at) if self.terms_accepted_at else None,
                'show_last_seen': self.show_last_seen,
                'show_profile_photo': self.show_profile_photo,
                'show_bio': self.show_bio,
                'is_2fa_enabled': self.is_2fa_enabled,
                'has_archive_pin': self.has_archive_pin,
                'is_admin': bool(self.is_admin),
            })
        return data


class UserDevice(db.Model):
    __tablename__ = 'user_devices'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)

    device_fingerprint = db.Column(db.String(255), nullable=False, index=True)
    mac_address = db.Column(db.String(64), nullable=True)
    device_name = db.Column(db.String(150), nullable=True)
    device_model = db.Column(db.String(150), nullable=True)
    os_version = db.Column(db.String(100), nullable=True)
    app_version = db.Column(db.String(50), nullable=True)
    user_agent = db.Column(db.Text, nullable=True)

    is_active = db.Column(db.Boolean, default=True)
    last_active = db.Column(db.DateTime, default=datetime.utcnow)

    # Soft Delete
    is_deleted = db.Column(db.Boolean, default=False)
    deleted_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    __table_args__ = (
        db.Index('idx_device_fingerprint', 'device_fingerprint'),
        db.UniqueConstraint('user_id', 'device_fingerprint', name='uq_user_device'),
    )


class UserSession(db.Model):
    __tablename__ = 'user_sessions'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    device_id = db.Column(db.String(36), db.ForeignKey('user_devices.id'), nullable=True)

    refresh_token = db.Column(db.String(512), unique=True, nullable=False)
    ip_address = db.Column(db.String(45), nullable=True)
    is_active = db.Column(db.Boolean, default=True)

    expires_at = db.Column(db.DateTime, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    last_used = db.Column(db.DateTime, default=datetime.utcnow)


class PhoneVerification(db.Model):
    """One-time, server-side phone verification challenge.

    The OTP is stored as a keyed digest in ``code_hash``. It is never returned
    by an API, written to the audit log, or persisted in clear text.
    """
    __tablename__ = 'phone_verifications'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=True, index=True)
    mobile_number = db.Column(db.String(16), nullable=False, index=True)
    purpose = db.Column(db.String(32), nullable=False, index=True)
    code_hash = db.Column(db.String(64), nullable=False)
    attempts = db.Column(db.Integer, nullable=False, default=0, server_default='0')
    expires_at = db.Column(db.DateTime, nullable=False, index=True)
    verified_at = db.Column(db.DateTime, nullable=True)
    consumed_at = db.Column(db.DateTime, nullable=True)
    revoked_at = db.Column(db.DateTime, nullable=True)
    ip_address = db.Column(db.String(45), nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)

    __table_args__ = (
        db.Index('idx_phone_verification_lookup', 'mobile_number', 'purpose', 'created_at'),
    )


class BlockList(db.Model):
    __tablename__ = 'block_list'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    blocker_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    blocked_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    # Soft Delete (unblock)
    is_deleted = db.Column(db.Boolean, default=False)
    deleted_at = db.Column(db.DateTime, nullable=True)

    __table_args__ = (
        db.UniqueConstraint('blocker_id', 'blocked_id', name='uq_block'),
    )
