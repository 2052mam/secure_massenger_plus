import json

from app.services.sms_ir import send_verification_code


class FakeResponse:
    status = 200

    def read(self):
        return b'{"status":1}'

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


def test_sms_ir_adapter_uses_verify_endpoint_and_configured_parameters(app, monkeypatch):
    captured = {}

    def fake_urlopen(request, timeout):
        captured['url'] = request.full_url
        captured['headers'] = request.headers
        captured['body'] = json.loads(request.data.decode('utf-8'))
        captured['timeout'] = timeout
        return FakeResponse()

    app.config.update(
        SMS_DELIVERY_MODE='sms_ir',
        SMS_IR_API_KEY='test-only-provider-key',
        SMS_IR_TEMPLATE_ID='12345',
        SMS_IR_TEMPLATE_PARAMETERS='{"CODE":"{code}","MOBILE":"{mobile}"}',
        SMS_IR_TIMEOUT_SECONDS=7,
    )
    monkeypatch.setattr('app.services.sms_ir.urlopen', fake_urlopen)
    with app.app_context():
        send_verification_code('+989121234567', '123456')

    assert captured['url'] == 'https://api.sms.ir/v1/send/verify'
    assert captured['body'] == {
        'mobile': '989121234567',
        'templateId': 12345,
        'parameters': [
            {'name': 'CODE', 'value': '123456'},
            {'name': 'MOBILE', 'value': '+989121234567'},
        ],
    }
    assert captured['timeout'] == 7
    assert captured['headers']['X-api-key'] == 'test-only-provider-key'
