"""Telegram-like Stories API (polling, 24h expiry, no WebSocket)."""
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.story import Story, StoryView
from app.models.user import User, BlockList
from app.models.chat import ChatMember
from app.models.media import MediaFile
from app.models.audit import AuditLog
from datetime import datetime, timedelta

stories_bp = Blueprint('stories', __name__)

STORY_TTL_HOURS = 24


def get_client_ip():
    return request.headers.get('X-Forwarded-For', request.remote_addr)


def _serialize_story(story, viewer_id):
    author = db.session.get(User, story.user_id)
    seen = StoryView.query.filter_by(story_id=story.id, viewer_id=viewer_id).first() is not None
    d = story.to_dict(viewer_has_seen=seen)
    d['author'] = author.to_dict() if author else None
    return d


def _visible_user_ids(viewer_id):
    """Users whose stories the viewer may see: anyone sharing a chat + self.

    Blocked users (either direction) are excluded.
    """
    from app.models.chat import Chat
    chat_ids = [m.chat_id for m in ChatMember.query.filter_by(
        user_id=viewer_id, is_deleted=False).all()]
    if not chat_ids:
        return {viewer_id}
    member_rows = ChatMember.query.filter(
        ChatMember.chat_id.in_(chat_ids),
        ChatMember.is_deleted.is_(False)).all()
    ids = {r.user_id for r in member_rows}
    ids.add(viewer_id)
    blocks = BlockList.query.filter(
        BlockList.is_deleted.is_(False),
        ((BlockList.blocker_id == viewer_id) | (BlockList.blocked_id == viewer_id))).all()
    for b in blocks:
        ids.discard(b.blocker_id if b.blocked_id == viewer_id else b.blocked_id)
    ids.add(viewer_id)
    return ids


@stories_bp.route('/', methods=['GET'])
@jwt_required()
def feed():
    """Story feed grouped by author (Telegram story tray order)."""
    viewer_id = get_jwt_identity()
    now = datetime.utcnow()
    # Purge expired (soft-delete) opportunistically.
    Story.query.filter(Story.expires_at <= now, Story.is_deleted.is_(False)).update(
        {'is_deleted': True, 'deleted_at': now}, synchronize_session=False)
    db.session.commit()
    allowed = _visible_user_ids(viewer_id)
    stories = Story.query.filter(
        Story.user_id.in_(allowed),
        Story.is_deleted.is_(False),
        Story.expires_at > now).order_by(Story.created_at.desc()).all()
    # Group by author, newest author first; unseen authors before seen ones.
    by_author = {}
    for s in stories:
        by_author.setdefault(s.user_id, []).append(s)
    groups = []
    for uid, items in by_author.items():
        items.sort(key=lambda s: s.created_at)
        author = db.session.get(User, uid)
        if not author or author.is_deleted:
            continue
        seen_all = all(StoryView.query.filter_by(story_id=s.id, viewer_id=viewer_id).first() is not None
                       for s in items) if uid != viewer_id else True
        groups.append({
            'user': author.to_dict(),
            'stories': [_serialize_story(s, viewer_id) for s in items],
            'has_unseen': (not seen_all) and uid != viewer_id,
            'latest_at': max(s.created_at for s in items).isoformat() + 'Z',
        })
    groups.sort(key=lambda g: (not g['has_unseen'], g['latest_at']), reverse=False)
    # Own stories first (Telegram shows "Your story" first).
    groups.sort(key=lambda g: (g['user']['id'] != viewer_id,))
    return jsonify({'groups': groups}), 200


@stories_bp.route('/', methods=['POST'])
@jwt_required()
def create_story():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    story_type = (data.get('story_type') or 'text').strip().lower()
    if story_type not in ('text', 'image', 'video'):
        return jsonify({'error': 'Invalid story type'}), 400
    content = (data.get('content') or '').strip()[:1000] or None
    media_id = data.get('media_id')
    if story_type == 'text' and not content:
        return jsonify({'error': 'متن استوری خالی است'}), 400
    if story_type in ('image', 'video') and not media_id:
        return jsonify({'error': 'فایل استوری الزامی است'}), 400
    if media_id:
        media = MediaFile.query.filter_by(id=media_id, uploader_id=user_id,
                                          is_deleted=False).first()
        if not media:
            return jsonify({'error': 'فایل در دسترس نیست'}), 403
        expected = 'image' if story_type == 'image' else 'video'
        if media.media_type != expected:
            return jsonify({'error': 'نوع فایل با نوع استوری مطابقت ندارد'}), 400
    privacy = (data.get('privacy') or 'everyone').strip().lower()
    if privacy not in ('everyone', 'contacts'):
        privacy = 'everyone'
    story = Story(user_id=user_id, story_type=story_type, content=content,
                  media_id=media_id, privacy=privacy,
                  expires_at=datetime.utcnow() + timedelta(hours=STORY_TTL_HOURS))
    db.session.add(story)
    db.session.add(AuditLog(actor_id=user_id, action='create_story',
                            entity_type='story', entity_id=story.id,
                            ip_address=get_client_ip()))
    db.session.commit()
    return jsonify(_serialize_story(story, user_id)), 201


@stories_bp.route('/mine', methods=['GET'])
@jwt_required()
def my_stories():
    user_id = get_jwt_identity()
    now = datetime.utcnow()
    stories = Story.query.filter_by(user_id=user_id, is_deleted=False).filter(
        Story.expires_at > now).order_by(Story.created_at.desc()).all()
    return jsonify({'stories': [_serialize_story(s, user_id) for s in stories]}), 200


@stories_bp.route('/<story_id>', methods=['GET'])
@jwt_required()
def get_story(story_id):
    viewer_id = get_jwt_identity()
    story = Story.query.filter_by(id=story_id, is_deleted=False).first()
    if not story or story.expires_at <= datetime.utcnow():
        return jsonify({'error': 'استوری یافت نشد'}), 404
    if story.user_id != viewer_id and story.user_id not in _visible_user_ids(viewer_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403
    return jsonify(_serialize_story(story, viewer_id)), 200


@stories_bp.route('/<story_id>/view', methods=['POST'])
@jwt_required()
def view_story(story_id):
    viewer_id = get_jwt_identity()
    story = Story.query.filter_by(id=story_id, is_deleted=False).first()
    if not story or story.expires_at <= datetime.utcnow():
        return jsonify({'error': 'استوری یافت نشد'}), 404
    if story.user_id != viewer_id and story.user_id not in _visible_user_ids(viewer_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403
    if story.user_id != viewer_id:
        existing = StoryView.query.filter_by(story_id=story_id, viewer_id=viewer_id).first()
        if not existing:
            db.session.add(StoryView(story_id=story_id, viewer_id=viewer_id))
            story.views_count = (story.views_count or 0) + 1
            db.session.commit()
    return jsonify({'ok': True, 'views_count': story.views_count or 0}), 200


@stories_bp.route('/<story_id>/views', methods=['GET'])
@jwt_required()
def story_views(story_id):
    viewer_id = get_jwt_identity()
    story = Story.query.filter_by(id=story_id, is_deleted=False).first()
    if not story:
        return jsonify({'error': 'استوری یافت نشد'}), 404
    if story.user_id != viewer_id:
        return jsonify({'error': 'فقط صاحب استوری می‌تواند بازدیدها را ببیند'}), 403
    views = StoryView.query.filter_by(story_id=story_id).order_by(
        StoryView.viewed_at.desc()).all()
    out = []
    for v in views:
        u = db.session.get(User, v.viewer_id)
        if u and not u.is_deleted:
            out.append({'user': u.to_dict(),
                        'viewed_at': v.viewed_at.isoformat() + 'Z' if v.viewed_at else None})
    return jsonify({'views': out, 'views_count': story.views_count or 0}), 200


@stories_bp.route('/<story_id>/delete', methods=['POST', 'DELETE'])
@jwt_required()
def delete_story(story_id):
    viewer_id = get_jwt_identity()
    story = Story.query.filter_by(id=story_id, user_id=viewer_id, is_deleted=False).first()
    if not story:
        return jsonify({'error': 'استوری یافت نشد'}), 404
    story.is_deleted = True
    story.deleted_at = datetime.utcnow()
    db.session.commit()
    return jsonify({'ok': True}), 200
