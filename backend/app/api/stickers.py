from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.sticker import StickerPack, Sticker
from app.models.media import MediaFile
from werkzeug.utils import secure_filename
import os, uuid

stickers_bp = Blueprint('stickers', __name__)

# Seed attractive packs on first request if empty
def ensure_seeded():
    if StickerPack.query.first() is not None:
        return
    packs_data = [
        {
            'name': 'cute_cats',
            'title': '🐱 گربه‌های بامزه',
            'thumbnail_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f431.png',
            'stickers': [
                {'emoji': '😺', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f63a.png'},
                {'emoji': '😸', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f638.png'},
                {'emoji': '😹', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f639.png'},
                {'emoji': '😻', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f63b.png'},
                {'emoji': '😼', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f63c.png'},
                {'emoji': '🙀', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f640.png'},
                {'emoji': '😿', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f63f.png'},
                {'emoji': '😾', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f63e.png'},
                {'emoji': '🐾', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f43e.png'},
                {'emoji': '🐈', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f408.png'},
                {'emoji': '🐈‍⬛', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f408-200d-2b1b.png'},
                {'emoji': '😽', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f63d.png'},
            ]
        },
        {
            'name': 'funny_dogs',
            'title': '🐶 سگ‌های باحال',
            'thumbnail_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f436.png',
            'stickers': [
                {'emoji': '🐶', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f436.png'},
                {'emoji': '🐕', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f415.png'},
                {'emoji': '🦮', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f9ae.png'},
                {'emoji': '🐩', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f429.png'},
                {'emoji': '🐺', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f43a.png'},
                {'emoji': '🦊', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f98a.png'},
                {'emoji': '🦝', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f99d.png'},
                {'emoji': '🐾', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f43e.png'},
                {'emoji': '🦴', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f9b4.png'},
                {'emoji': '😄', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f604.png'},
                {'emoji': '🥰', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f970.png'},
                {'emoji': '🤩', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f929.png'},
            ]
        },
        {
            'name': 'persian_love',
            'title': '❤️ عشق پارسی',
            'thumbnail_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2764-fe0f.png',
            'stickers': [
                {'emoji': '❤️', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2764.png'},
                {'emoji': '💖', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f496.png'},
                {'emoji': '💕', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f495.png'},
                {'emoji': '💞', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f49e.png'},
                {'emoji': '💓', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f493.png'},
                {'emoji': '💗', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f497.png'},
                {'emoji': '💝', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f49d.png'},
                {'emoji': '🌹', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f339.png'},
                {'emoji': '😘', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f618.png'},
                {'emoji': '🥰', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f970.png'},
                {'emoji': '😍', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f60d.png'},
                {'emoji': '🤗', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f917.png'},
            ]
        },
        {
            'name': 'telegram_emotions',
            'title': '😂 احساسات تلگرامی',
            'thumbnail_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f602.png',
            'stickers': [
                {'emoji': '😂', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f602.png'},
                {'emoji': '🤣', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f923.png'},
                {'emoji': '😆', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f606.png'},
                {'emoji': '😅', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f605.png'},
                {'emoji': '🥲', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f972.png'},
                {'emoji': '😇', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f607.png'},
                {'emoji': '🤔', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f914.png'},
                {'emoji': '🤯', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f92f.png'},
                {'emoji': '🥳', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f973.png'},
                {'emoji': '😎', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f60e.png'},
                {'emoji': '🤩', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f929.png'},
                {'emoji': '😴', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f634.png'},
            ]
        },
        {
            'name': 'iran_culture',
            'title': '🇮🇷 فرهنگ ایران',
            'thumbnail_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f1ee-1f1f7.png',
            'stickers': [
                {'emoji': '🇮🇷', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f1ee-1f1f7.png'},
                {'emoji': '🕌', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f54c.png'},
                {'emoji': '🍵', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f375.png'},
                {'emoji': '🌙', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f319.png'},
                {'emoji': '⭐', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2b50.png'},
                {'emoji': '🎉', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f389.png'},
                {'emoji': '🪴', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1fab4.png'},
                {'emoji': '🍉', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f349.png'},
                {'emoji': '🧿', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f9ff.png'},
                {'emoji': '📿', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f4ff.png'},
                {'emoji': '🎨', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f3a8.png'},
                {'emoji': '🕊️', 'file_url': 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f54a.png'},
            ]
        },
    ]
    for pack in packs_data:
        p = StickerPack(name=pack['name'], title=pack['title'], thumbnail_url=pack['thumbnail_url'])
        db.session.add(p)
        db.session.flush()
        for idx, s in enumerate(pack['stickers']):
            db.session.add(Sticker(pack_id=p.id, emoji=s['emoji'], file_url=s['file_url'], position=idx, width=512, height=512))
    db.session.commit()

@stickers_bp.before_request
def seed_before():
    try:
        ensure_seeded()
    except Exception:
        pass

@stickers_bp.route('/packs', methods=['GET'])
@jwt_required(optional=True)
def list_packs():
    ensure_seeded()
    packs = StickerPack.query.filter_by(is_featured=True).all()
    return jsonify({'packs': [p.to_dict() for p in packs]}), 200

@stickers_bp.route('/packs/<pack_id>', methods=['GET'])
@jwt_required(optional=True)
def get_pack(pack_id):
    ensure_seeded()
    pack = StickerPack.query.filter_by(id=pack_id).first()
    if not pack:
        # also allow lookup by name
        pack = StickerPack.query.filter_by(name=pack_id).first()
    if not pack:
        return jsonify({'error': 'پک یافت نشد'}), 404
    return jsonify({'pack': pack.to_dict(include_stickers=True)}), 200

@stickers_bp.route('/packs/<pack_id>/stickers', methods=['GET'])
@jwt_required(optional=True)
def list_stickers(pack_id):
    ensure_seeded()
    pack = StickerPack.query.filter_by(id=pack_id).first() or StickerPack.query.filter_by(name=pack_id).first()
    if not pack:
        return jsonify({'error': 'پک یافت نشد'}), 404
    stickers = Sticker.query.filter_by(pack_id=pack.id, is_deleted=False).order_by(Sticker.position.asc()).all()
    return jsonify({'stickers': [s.to_dict() for s in stickers]}), 200

@stickers_bp.route('/trending', methods=['GET'])
@jwt_required(optional=True)
def trending_stickers():
    ensure_seeded()
    # return first pack's stickers as trending
    pack = StickerPack.query.first()
    if not pack:
        return jsonify({'stickers': []}), 200
    stickers = Sticker.query.filter_by(pack_id=pack.id, is_deleted=False).limit(12).all()
    return jsonify({'stickers': [s.to_dict() for s in stickers]}), 200
