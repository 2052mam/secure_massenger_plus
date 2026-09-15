from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.message import Message, MessageReaction
from app.models.chat import Chat, ChatMember
from app.models.user import User
from app.services.message_payloads import user_in_chat
from datetime import datetime

reactions_bp = Blueprint('reactions', __name__)

# Telegram-like quick reactions
ALLOWED_EMOJIS = {
    '❤️', '👍', '👎', '🔥', '😂', '😮', '😢', '🙏', '👏', '🎉',
    '🤔', '🤯', '😍', '🥰', '🤩', '😎', '🥳', '😭', '😡', '🤬',
    '👌', '💯', '✅', '❌', '⚡', '💩', '🤡', '👻', '💔', '🌟',
    '🥺', '😇', '🤗', '🤭', '🤫', '🤐', '😐', '😑', '😶', '🙄',
    # allow any single emoji; we validate length <= 10 and not empty
}

def normalize_emoji(value):
    if not isinstance(value, str):
        return None
    e = value.strip()
    if not e or len(e) > 20:
        return None
    # If in allowed set, ok; otherwise allow any emoji with length <= 10 chars
    # Reject plain text with spaces
    if ' ' in e and len(e) > 4:
        return None
    return e

@reactions_bp.route('/<message_id>/reaction', methods=['POST'])
@jwt_required()
def toggle_reaction(message_id):
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    emoji = normalize_emoji(data.get('emoji') or data.get('reaction') or '')
    if not emoji:
        return jsonify({'error': 'ایموجی نامعتبر است'}), 400
    msg = Message.query.filter_by(id=message_id, is_deleted=False, is_deleted_for_all=False).first()
    if not msg:
        return jsonify({'error': 'پیام یافت نشد'}), 404
    if not user_in_chat(user_id, msg.chat_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403
    # Telegram: reactions allowed in private, group, channel (if not restricted)
    # For channels, check if user is member
    # Check message is not scheduled
    if msg.is_scheduled:
        return jsonify({'error': 'پیام زمان‌بندی‌شده قابل ری‌اکشن نیست'}), 400

    # Telegram allows one reaction per user per message by default (replace old)
    # But our model allows unique per emoji; we implement single-emoji-per-user: remove previous different emoji
    existing_others = MessageReaction.query.filter_by(message_id=message_id, user_id=user_id, is_deleted=False).all()
    # If same emoji exists, toggle off (remove)
    for r in existing_others:
        if r.emoji == emoji:
            r.is_deleted = True
            r.deleted_at = datetime.utcnow()
            db.session.commit()
            return jsonify({'ok': True, 'action': 'removed', 'emoji': emoji, 'reactions': reaction_summary(message_id, user_id)}), 200
    # If user already reacted with different emoji, remove old ones (Telegram replaces)
    for r in existing_others:
        r.is_deleted = True
        r.deleted_at = datetime.utcnow()
    # Add new reaction
    new = MessageReaction(message_id=message_id, user_id=user_id, emoji=emoji)
    db.session.add(new)
    db.session.commit()
    return jsonify({'ok': True, 'action': 'added', 'emoji': emoji, 'reactions': reaction_summary(message_id, user_id)}), 200

@reactions_bp.route('/<message_id>/reactions', methods=['GET'])
@jwt_required()
def list_reactions(message_id):
    user_id = get_jwt_identity()
    msg = Message.query.filter_by(id=message_id).first()
    if not msg or not user_in_chat(user_id, msg.chat_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403
    return jsonify(reaction_summary(message_id, user_id)), 200

@reactions_bp.route('/<message_id>/reaction', methods=['DELETE'])
@jwt_required()
def remove_reaction(message_id):
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    emoji = normalize_emoji(data.get('emoji') or '') if data else None
    query = MessageReaction.query.filter_by(message_id=message_id, user_id=user_id, is_deleted=False)
    if emoji:
        query = query.filter_by(emoji=emoji)
    reactions = query.all()
    if not reactions:
        return jsonify({'ok': True, 'message': 'ری‌اکشنی یافت نشد'}), 200
    for r in reactions:
        r.is_deleted = True
        r.deleted_at = datetime.utcnow()
    db.session.commit()
    return jsonify({'ok': True, 'removed': len(reactions), 'reactions': reaction_summary(message_id, user_id)}), 200

def reaction_summary(message_id, viewer_id=None):
    reactions = MessageReaction.query.filter_by(message_id=message_id, is_deleted=False).all()
    # group by emoji
    counts = {}
    user_reacted = {}
    for r in reactions:
        counts[r.emoji] = counts.get(r.emoji, 0) + 1
        if r.user_id == viewer_id:
            user_reacted[r.emoji] = True
    # Build sorted list by count desc
    summary = [{'emoji': e, 'count': c, 'me': bool(user_reacted.get(e))} for e, c in sorted(counts.items(), key=lambda x: -x[1])]
    # also include recent users for avatar preview? fetch up to 3 users per emoji
    details = []
    for item in summary:
        emoji = item['emoji']
        users = [u for u in reactions if u.emoji == emoji][:3]
        user_infos = []
        for rr in users:
            u = User.query.get(rr.user_id)
            if u:
                user_infos.append({'id': u.id, 'display_name': u.display_name, 'username': u.username})
        details.append({**item, 'users': user_infos})
    return {'reactions': details, 'total': len(reactions)}
