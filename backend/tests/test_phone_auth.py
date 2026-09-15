from datetime import datetime, timedelta

import pyotp

from app import db
from app.models.user import PhoneVerification, User


def device(device_id='phone-test-device'):
    return {
        'device_id': device_id,
        'model': 'Test Phone',
        'os': 'Android',
        'device_name': 'Test Phone',
    }


def register(client, mobile='09121234567', **extra):
    body = {
        'email': 'phone-user@example.test',
        'password': 'Password-123!',
        'display_name': 'Phone User',
        'mobile_number': mobile,
        'username': 'phone_user',
        'terms_accepted': True,
        'terms_version': 1,
        'device_info': device(),
    }
    body.update(extra)
    return client.post('/api/v1/auth/register', json=body)


def test_registration_requires_a_phone_and_never_returns_a_totp_secret(client):
    response = register(client, mobile='not a phone')
    assert response.status_code == 400
    assert 'totp_secret' not in response.json


def test_phone_registration_sends_code_activates_account_and_creates_session(app, client):
    delivered = []
    app.config['SMS_SENDER'] = lambda mobile, code: delivered.append((mobile, code))

    response = register(client)
    assert response.status_code == 201
    assert set(response.json).isdisjoint({'totp_secret', 'totp_uri'})
    assert response.json['mobile_number'].startswith('+989')
    assert len(delivered) == 1
    assert delivered[0][0] == '+989121234567'

    with app.app_context():
        user = User.query.filter_by(email='phone-user@example.test').one()
        assert user.is_active is False
        assert user.mobile_number == '+989121234567'
        assert user.mobile_verified_at is None
        assert user.is_2fa_enabled is False
        assert PhoneVerification.query.filter_by(user_id=user.id).count() == 1

    verified = client.post('/api/v1/auth/verify-phone', json={
        'verification_id': response.json['verification_id'],
        'code': delivered[-1][1],
        'device_info': device(),
    })
    assert verified.status_code == 200
    assert verified.json['access_token']
    assert verified.json['refresh_token']
    assert verified.json['user']['mobile_number'] == '+989121234567'
    assert verified.json['user']['is_2fa_enabled'] is False

    with app.app_context():
        user = User.query.filter_by(email='phone-user@example.test').one()
        challenge = db.session.get(PhoneVerification, response.json['verification_id'])
        assert user.is_active is True
        assert user.mobile_verified_at is not None
        assert challenge.consumed_at is not None
        assert delivered[-1][1] not in challenge.code_hash


def test_phone_login_is_primary_and_unknown_numbers_are_not_enumerated(app, client):
    delivered = []
    app.config['SMS_SENDER'] = lambda mobile, code: delivered.append((mobile, code))
    registration = register(client)
    verified = client.post('/api/v1/auth/verify-phone', json={
        'verification_id': registration.json['verification_id'],
        'code': delivered[-1][1],
        'device_info': device(),
    })
    assert verified.status_code == 200

    known = client.post('/api/v1/auth/request-phone-code', json={
        'mobile_number': '+989121234567',
    })
    unknown = client.post('/api/v1/auth/request-phone-code', json={
        'mobile_number': '+989121234568',
    })
    assert known.status_code == unknown.status_code == 202
    assert known.json['message'] == unknown.json['message']
    assert len(delivered) == 2  # Unknown number was not sent an SMS.

    signed_in = client.post('/api/v1/auth/verify-phone', json={
        'verification_id': known.json['verification_id'],
        'code': delivered[-1][1],
        'device_info': device('second-device'),
    })
    assert signed_in.status_code == 200
    assert signed_in.json['user']['id'] == verified.json['user']['id']

    fake = client.post('/api/v1/auth/verify-phone', json={
        'verification_id': unknown.json['verification_id'],
        'code': '000000',
        'device_info': device(),
    })
    assert fake.status_code == 401


def test_resend_invalidates_the_previous_sms_code(app, client):
    delivered = []
    app.config.update(
        SMS_SENDER=lambda mobile, code: delivered.append((mobile, code)),
        PHONE_CODE_RESEND_SECONDS=0,
    )
    first = register(client)
    assert first.status_code == 201
    first_code = delivered[-1][1]
    second = client.post('/api/v1/auth/resend-phone-code', json={
        'verification_id': first.json['verification_id'],
    })
    assert second.status_code == 202
    assert second.json['verification_id'] != first.json['verification_id']

    stale = client.post('/api/v1/auth/verify-phone', json={
        'verification_id': first.json['verification_id'],
        'code': first_code,
        'device_info': device(),
    })
    assert stale.status_code == 401
    current = client.post('/api/v1/auth/verify-phone', json={
        'verification_id': second.json['verification_id'],
        'code': delivered[-1][1],
        'device_info': device(),
    })
    assert current.status_code == 200


def test_optional_google_authenticator_follows_sms_verification(app, client):
    delivered = []
    app.config['SMS_SENDER'] = lambda mobile, code: delivered.append((mobile, code))
    registration = register(client)
    first_login = client.post('/api/v1/auth/verify-phone', json={
        'verification_id': registration.json['verification_id'],
        'code': delivered[-1][1],
        'device_info': device(),
    })
    assert first_login.status_code == 200
    headers = {'Authorization': f"Bearer {first_login.json['access_token']}"}

    setup = client.post('/api/v1/auth/2fa/setup', headers=headers, json={})
    assert setup.status_code == 200
    secret = setup.json['totp_secret']
    assert setup.json['totp_uri'].startswith('otpauth://totp/')

    enabled = client.post('/api/v1/auth/2fa/enable', headers=headers, json={
        'code': pyotp.TOTP(secret).now(),
    })
    assert enabled.status_code == 200
    assert enabled.json['user']['is_2fa_enabled'] is True

    requested = client.post('/api/v1/auth/request-phone-code', json={
        'mobile_number': '09121234567',
    })
    assert requested.status_code == 202
    sms_verified = client.post('/api/v1/auth/verify-phone', json={
        'verification_id': requested.json['verification_id'],
        'code': delivered[-1][1],
        'device_info': device('two-factor-device'),
    })
    assert sms_verified.status_code == 200
    assert sms_verified.json == {
        'require_2fa': True,
        'verification_id': requested.json['verification_id'],
        'message': 'کد Google Authenticator را وارد کنید.',
    }

    completed = client.post('/api/v1/auth/verify-login-2fa', json={
        'verification_id': requested.json['verification_id'],
        'code': pyotp.TOTP(secret).now(),
        'device_info': device('two-factor-device'),
    })
    assert completed.status_code == 200
    assert completed.json['access_token']

    reused = client.post('/api/v1/auth/verify-login-2fa', json={
        'verification_id': requested.json['verification_id'],
        'code': pyotp.TOTP(secret).now(),
        'device_info': device('two-factor-device'),
    })
    assert reused.status_code == 401


def test_codes_expire_and_old_email_login_still_works(app, client):
    delivered = []
    app.config['SMS_SENDER'] = lambda mobile, code: delivered.append((mobile, code))
    response = register(client)
    with app.app_context():
        challenge = db.session.get(PhoneVerification, response.json['verification_id'])
        challenge.expires_at = datetime.utcnow() - timedelta(seconds=1)
        db.session.commit()
    expired = client.post('/api/v1/auth/verify-phone', json={
        'verification_id': response.json['verification_id'],
        'code': delivered[-1][1],
        'device_info': device(),
    })
    assert expired.status_code == 410

    with app.app_context():
        legacy = User(
            id='legacy-phone-auth',
            email='legacy@example.test',
            username='legacy_phone_auth',
            display_name='Legacy',
            totp_secret='JBSWY3DPEHPK3PXP',
            is_2fa_enabled=True,
        )
        legacy.set_password('LegacyPass-123!')
        db.session.add(legacy)
        db.session.commit()
        code = pyotp.TOTP(legacy.totp_secret).now()
    old_login = client.post('/api/v1/auth/login', json={
        'email': 'legacy@example.test',
        'password': 'LegacyPass-123!',
        'totp_code': code,
        'device_info': device('legacy-device'),
    })
    assert old_login.status_code == 200
    assert old_login.json['user']['id'] == 'legacy-phone-auth'


def test_resend_rate_limit_and_totp_setup_requires_a_session(app, client):
    delivered = []
    app.config['SMS_SENDER'] = lambda mobile, code: delivered.append((mobile, code))
    response = register(client)
    too_soon = client.post('/api/v1/auth/resend-phone-code', json={
        'verification_id': response.json['verification_id'],
    })
    assert too_soon.status_code == 429
    assert client.post('/api/v1/auth/2fa/setup', json={}).status_code in {401, 422}
