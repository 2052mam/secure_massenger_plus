"""SMS.ir delivery adapter for one-time phone verification codes.

The mobile app never calls SMS.ir directly and never receives the provider key.
Set the provider configuration in the backend environment (see .env.example).
"""
from __future__ import annotations

import json
from typing import Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from flask import current_app


class SmsDeliveryError(RuntimeError):
    """A safe, provider-neutral delivery failure for the public API."""


def _provider_mobile(mobile_number: str) -> str:
    """SMS.ir expects digits, without an E.164 plus sign."""
    return mobile_number.lstrip('+')


def _template_parameters(code: str, mobile_number: str) -> list[dict[str, str]]:
    """Build SMS.ir's parameter list without putting template details in code.

    ``SMS_IR_TEMPLATE_PARAMETERS`` may be a JSON object, for example:
    {"CODE":"{code}","APP":"SecureMessenger"}
    The {code} and {mobile} tokens are substituted at send time.  A single
    CODE parameter is used by default, which matches SMS.ir's own example.
    """
    raw = current_app.config.get('SMS_IR_TEMPLATE_PARAMETERS', '')
    if raw:
        try:
            configured = json.loads(raw)
        except (TypeError, json.JSONDecodeError) as error:
            raise SmsDeliveryError('SMS template parameters are invalid.') from error
        if not isinstance(configured, dict) or not configured:
            raise SmsDeliveryError('SMS template parameters are invalid.')
    else:
        configured = {
            current_app.config.get('SMS_IR_CODE_PARAMETER', 'CODE'): '{code}',
        }

    parameters: list[dict[str, str]] = []
    for name, value in configured.items():
        if not isinstance(name, str) or not name.strip() or not isinstance(value, str):
            raise SmsDeliveryError('SMS template parameters are invalid.')
        parameters.append({
            'name': name.strip(),
            'value': value.replace('{code}', code).replace('{mobile}', mobile_number),
        })
    return parameters


def send_verification_code(mobile_number: str, code: str) -> None:
    """Send a verification code using the configured delivery mode.

    ``console`` is deliberately available only for local/manual development:
    it logs a code to the *server* log and never returns it from an API.  Tests
    can inject a callable through ``SMS_SENDER`` to capture a code without a
    network request.  Production uses SMS.ir over HTTPS.
    """
    custom_sender: Callable[[str, str], None] | None = current_app.config.get('SMS_SENDER')
    if custom_sender is not None:
        custom_sender(mobile_number, code)
        return

    mode = str(current_app.config.get('SMS_DELIVERY_MODE', 'sms_ir')).lower()
    if mode == 'console':
        current_app.logger.warning(
            'Development phone verification code for %s: %s', mobile_number, code,
        )
        return
    if mode != 'sms_ir':
        raise SmsDeliveryError('SMS delivery is not configured.')

    api_key = current_app.config.get('SMS_IR_API_KEY')
    template_id = current_app.config.get('SMS_IR_TEMPLATE_ID')
    if not api_key or not template_id:
        raise SmsDeliveryError('SMS.ir credentials or template ID are missing.')
    try:
        template_id = int(template_id)
    except (TypeError, ValueError) as error:
        raise SmsDeliveryError('SMS.ir template ID is invalid.') from error

    payload = {
        'mobile': _provider_mobile(mobile_number),
        'templateId': template_id,
        'parameters': _template_parameters(code, mobile_number),
    }
    request = Request(
        'https://api.sms.ir/v1/send/verify',
        data=json.dumps(payload).encode('utf-8'),
        headers={
            'Content-Type': 'application/json',
            'Accept': 'text/plain',
            'x-api-key': api_key,
        },
        method='POST',
    )
    timeout = float(current_app.config.get('SMS_IR_TIMEOUT_SECONDS', 10))
    try:
        with urlopen(request, timeout=timeout) as response:
            # Consume the body so HTTP errors and proxies are handled before
            # the verification challenge is committed to the database.
            response.read()
            if not 200 <= response.status < 300:
                raise SmsDeliveryError('SMS.ir rejected the verification request.')
    except HTTPError as error:
        current_app.logger.warning('SMS.ir returned HTTP %s.', error.code)
        raise SmsDeliveryError('SMS.ir could not send the code.') from error
    except (URLError, OSError, TimeoutError) as error:
        current_app.logger.warning('SMS.ir delivery request failed: %s', type(error).__name__)
        raise SmsDeliveryError('SMS.ir could not send the code.') from error
