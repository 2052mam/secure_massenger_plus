"""Reject ambiguous JSON before mutation (e.g. bool('false') is True)."""
from flask import request, jsonify

BOOLEAN_FIELDS = {'for_all', 'is_view_once', 'is_public', 'is_muted',
                  'show_last_seen', 'show_profile_photo', 'show_bio',
                  'allow_group_adds', 'is_online', 'is_pinned', 'is_archived'}


def validate_object_body():
    if request.method not in ('POST', 'PUT', 'PATCH') or not request.is_json:
        return None
    data = request.get_json()
    if not isinstance(data, dict):
        return jsonify({'error': 'Expected a JSON object'}), 400
    if any(key in data and type(data[key]) is not bool for key in BOOLEAN_FIELDS):
        return jsonify({'error': 'Boolean fields must be true or false'}), 400
    return None
