"""Telegram-like saved GIFs — user library only.

Design (per product decision):
- NO online / trending GIFs (no Giphy/Tenor, no external network).
- NO "make GIF from video" (removed entirely).
- Users add GIFs they downloaded from the Internet by uploading the .gif
  file (via /media/upload) and saving it here. The GIF tab then shows only
  the user's own saved GIFs, and sending reuses the uploaded media.

This keeps the feature correct, offline-friendly and crash-free.
"""
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.gif import SavedGif
from app.models.media import MediaFile

gifs_bp = Blueprint('gifs', __name__)


def _saved_payload(gif):
    d = gif.to_dict()
    # Attach a usable media URL for locally uploaded GIFs so clients can
    # render them with auth headers (relative URL resolved by the app).
    if gif.media_id:
        d['media_url'] = f'/api/v1/media/{gif.media_id}'
    return d


@gifs_bp.route('/trending', methods=['GET'])
@jwt_required(optional=True)
def trending():
    # Online GIFs removed by product decision: return the user's saved GIFs
    # (or empty for guests) so old clients degrade gracefully.
    try:
        from flask_jwt_extended import get_jwt_identity as _ident
        user_id = _ident()
    except Exception:
        user_id = None
    if not user_id:
        return jsonify({'gifs': [], 'total': 0, 'online_disabled': True}), 200
    gifs = SavedGif.query.filter_by(user_id=user_id, is_deleted=False).order_by(
        SavedGif.created_at.desc()).all()
    return jsonify({'gifs': [_saved_payload(g) for g in gifs],
                    'total': len(gifs), 'online_disabled': True}), 200


@gifs_bp.route('/search', methods=['GET'])
@jwt_required(optional=True)
def search():
    # Search inside the user's own saved GIFs (no online search).
    try:
        from flask_jwt_extended import get_jwt_identity as _ident
        user_id = _ident()
    except Exception:
        user_id = None
    q = (request.args.get('q') or '').strip().lower()
    if not user_id:
        return jsonify({'gifs': [], 'total': 0, 'online_disabled': True}), 200
    query = SavedGif.query.filter_by(user_id=user_id, is_deleted=False)
    gifs = query.order_by(SavedGif.created_at.desc()).all()
    if q:
        gifs = [g for g in gifs if q in (g.title or '').lower()]
    try:
        limit = min(int(request.args.get('limit', 50)), 100)
    except (TypeError, ValueError):
        limit = 50
    gifs = gifs[:limit]
    return jsonify({'gifs': [_saved_payload(g) for g in gifs],
                    'total': len(gifs), 'online_disabled': True}), 200


@gifs_bp.route('/saved', methods=['GET'])
@jwt_required()
def list_saved():
    user_id = get_jwt_identity()
    gifs = SavedGif.query.filter_by(user_id=user_id, is_deleted=False).order_by(
        SavedGif.created_at.desc()).all()
    return jsonify({'gifs': [_saved_payload(g) for g in gifs]}), 200


@gifs_bp.route('/save', methods=['POST'])
@jwt_required()
def save_gif():
    """Save an uploaded .gif to the user's GIF library.

    Preferred body: {"media_id": "<uploaded gif media id>", "title": "..."}.
    Legacy external URLs are still accepted for backwards compatibility but
    the app no longer offers online GIFs.
    """
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    gif_url = (data.get('gif_url') or data.get('url') or '').strip()
    media_id = data.get('media_id')
    external_id = data.get('external_id') or data.get('id')
    title = (data.get('title') or '').strip()[:200]
    preview_url = (data.get('preview_url') or data.get('preview') or '').strip()
    if not gif_url and not media_id:
        return jsonify({'error': 'gif_url یا media_id الزامی است'}), 400
    if media_id:
        media = MediaFile.query.filter_by(id=media_id, uploader_id=user_id,
                                          is_deleted=False).first()
        if not media:
            return jsonify({'error': 'فایل یافت نشد'}), 404
        # Only real GIF uploads can join the GIF library (downloaded from the
        # Internet and uploaded by the user). Reject videos/documents.
        name = (media.original_name or '').lower()
        mime = (media.mime_type or '').lower()
        is_gif = name.endswith('.gif') or mime == 'image/gif'
        if not is_gif:
            return jsonify({'error': 'فقط فایل GIF مجاز است (فایل .gif آپلود کنید)'}), 400
        if not gif_url:
            gif_url = f'/api/v1/media/{media_id}'
        if not preview_url:
            preview_url = gif_url
    # Prevent duplicates
    existing = None
    if media_id:
        existing = SavedGif.query.filter_by(user_id=user_id, media_id=media_id,
                                            is_deleted=False).first()
    elif gif_url:
        existing = SavedGif.query.filter_by(user_id=user_id, gif_url=gif_url,
                                            is_deleted=False).first()
    if existing:
        return jsonify({'gif': _saved_payload(existing),
                        'message': 'قبلاً ذخیره شده'}), 200
    count = SavedGif.query.filter_by(user_id=user_id, is_deleted=False).count()
    if count >= 200:
        return jsonify({'error': 'حداکثر ۲۰۰ گیف ذخیره می‌شود'}), 400
    gif = SavedGif(user_id=user_id, gif_url=gif_url or None, media_id=media_id,
                   external_id=external_id, title=title or None,
                   preview_url=preview_url or None)
    db.session.add(gif)
    db.session.commit()
    return jsonify({'gif': _saved_payload(gif)}), 201


@gifs_bp.route('/saved/<gif_id>', methods=['DELETE', 'POST'])
@jwt_required()
def unsave_gif(gif_id):
    user_id = get_jwt_identity()
    gif = SavedGif.query.filter_by(id=gif_id, user_id=user_id,
                                   is_deleted=False).first()
    if not gif:
        gif = SavedGif.query.filter_by(gif_url=gif_id, user_id=user_id,
                                       is_deleted=False).first()
    if not gif:
        return jsonify({'error': 'گیف یافت نشد'}), 404
    gif.is_deleted = True
    db.session.commit()
    return jsonify({'ok': True}), 200


@gifs_bp.route('/make', methods=['POST'])
@jwt_required()
def make_gif():
    # "Make GIF from video" was removed by product decision.
    return jsonify({'error': 'ساخت گیف از ویدیو حذف شده است. فایل GIF را مستقیم آپلود و ذخیره کنید.',
                    'removed': True}), 410
