from flask import Blueprint, request, jsonify, current_app, send_from_directory
from flask_jwt_extended import jwt_required, get_jwt_identity
from werkzeug.utils import secure_filename
from app import db
from app.models.media import MediaFile
from app.models.message import Message
from app.models.audit import AuditLog
from datetime import datetime
import os
import shutil
import subprocess
import uuid

media_bp = Blueprint('media', __name__)

# Telegram-like: accept any common file type, not just a tiny whitelist.
# Keep a set for mime mapping; but allow any file extension like Telegram does.
ALLOWED_EXTENSIONS = {
    # images
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'svg', 'heic', 'heif',
    # videos
    'mp4', 'mov', 'webm', 'mkv', 'avi', 'flv', 'm4v', '3gp', 'mpeg', 'mpg', 'ogv',
    # audio
    'mp3', 'ogg', 'm4a', 'wav', 'flac', 'aac', 'wma', 'opus', 'aiff', 'amr',
    # documents & archives & executables (Telegram allows apk, zip, rar etc.)
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'csv', 'md',
    'json', 'xml', 'html', 'htm', 'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz',
    'apk', 'ipa', 'exe', 'dmg', 'iso', 'torrent', 'psd', 'ai', 'eps',
}

def allowed_file(filename):
    # Telegram allows virtually any file. We only reject empty names or
    # path traversal. If extension exists we check known list, but unknown
    # extensions are still allowed as 'document' (e.g. .log, .dat, .bin, custom).
    if not filename or filename.strip() == '':
        return False
    # secure_filename will have stripped path; just ensure we have a name
    name = filename.strip()
    if '/' in name or '\\' in name or '..' in name:
        return False
    if '.' not in name:
        # allow extension-less files like Telegram (e.g. LICENSE, Dockerfile)
        return len(name) <= 255
    ext = name.rsplit('.', 1)[1].lower()
    if not ext or len(ext) > 20:
        return False
    # Allow both known and unknown extensions; only block extremely long or empty
    return True

def get_media_type(ext):
    ext = ext.lower()
    if ext in {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'svg', 'heic', 'heif'}:
        return 'image'
    if ext in {'mp4', 'mov', 'webm', 'mkv', 'avi', 'flv', 'm4v', '3gp', 'mpeg', 'mpg', 'ogv'}:
        return 'video'
    if ext in {'mp3', 'ogg', 'm4a', 'wav', 'flac', 'aac', 'wma', 'opus', 'aiff', 'amr'}:
        return 'audio'
    return 'document'


@media_bp.route('/upload', methods=['POST'])
@jwt_required()
def upload_media():
    user_id = get_jwt_identity()

    if 'file' not in request.files:
        return jsonify({'error': 'فایل ارسال نشده'}), 400

    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'نام فایل خالی است'}), 400

    if not allowed_file(file.filename):
        return jsonify({'error': 'نوع فایل مجاز نیست'}), 400

    original_name = secure_filename(file.filename) or f"file_{uuid.uuid4().hex}"
    if '.' in original_name:
        ext = original_name.rsplit('.', 1)[1].lower()
        stored_name = f"{uuid.uuid4().hex}.{ext}"
    else:
        ext = ''
        stored_name = f"{uuid.uuid4().hex}"
    upload_folder = current_app.config['UPLOAD_FOLDER']
    os.makedirs(upload_folder, exist_ok=True)
    file_path = os.path.abspath(os.path.join(upload_folder, stored_name))
    file.save(file_path)

    # Optional video-editor trim (start/end in ms). Applied server-side with
    # ffmpeg when available; otherwise the full video is kept (graceful).
    try:
        trim_start = request.form.get('trim_start_ms')
        trim_end = request.form.get('trim_end_ms')
        if (trim_start or trim_end) and get_media_type(ext) == 'video' and shutil.which('ffmpeg'):
            start_s = max(0, int(trim_start or 0)) / 1000.0
            end_s = int(trim_end) / 1000.0 if trim_end and int(trim_end) > 0 else None
            if end_s is None or end_s > start_s:
                tmp_path = file_path + '.trim.mp4'
                cmd = ['ffmpeg', '-y', '-ss', str(start_s), '-i', file_path]
                if end_s is not None:
                    cmd += ['-t', str(end_s - start_s)]
                cmd += ['-c', 'copy', tmp_path]
                proc = subprocess.run(cmd, capture_output=True, timeout=120)
                if proc.returncode == 0 and os.path.getsize(tmp_path) > 0:
                    os.replace(tmp_path, file_path)
                elif os.path.exists(tmp_path):
                    os.remove(tmp_path)
    except Exception:
        pass  # Never fail an upload because trimming is unavailable.

    file_size = os.path.getsize(file_path)
    media_type = get_media_type(ext)

    # Optional music metadata sent by the client (Telegram-like player).
    title = (request.form.get('title') or '').strip()[:200] or None
    artist = (request.form.get('artist') or '').strip()[:200] or None
    duration = None
    if request.form.get('duration'):
        try:
            duration = float(request.form.get('duration'))
            if duration < 0 or duration > 24 * 3600:
                duration = None
        except (TypeError, ValueError):
            duration = None

    media = MediaFile(
        uploader_id=user_id,
        original_name=original_name,
        stored_name=stored_name,
        mime_type=file.mimetype or (f'application/{ext}' if ext else 'application/octet-stream'),
        file_size=file_size,
        file_path=file_path,
        media_type=media_type,
        title=title,
        artist=artist,
        duration=duration,
    )
    db.session.add(media)
    db.session.add(AuditLog(
        actor_id=user_id, action='upload_media', entity_type='media', entity_id=media.id
    ))
    db.session.commit()

    return jsonify({
        'id': media.id,
        'original_name': media.original_name,
        'media_type': media.media_type,
        'file_size': media.file_size,
        'title': media.title,
        'artist': media.artist,
        'duration': media.duration,
        'url': f'/api/v1/media/{media.id}',
    }), 201


@media_bp.route('/<media_id>', methods=['GET'])
@jwt_required()
def get_media(media_id):
    media = MediaFile.query.filter_by(id=media_id, is_deleted=False).first()
    if not media:
        return jsonify({'error': 'فایل یافت نشد'}), 404
    # Include deleted references: soft-deleting the message must not make its
    # ephemeral upload replayable through this generic, cacheable URL.
    if Message.query.filter_by(media_id=media_id, is_view_once=True).first():
        return jsonify({'error': 'عکس یک‌بارمصرف فقط از داخل پیام باز می‌شود'}), 403
    upload_folder = os.path.abspath(current_app.config['UPLOAD_FOLDER'])
    download = request.args.get('download') in ('1', 'true', 'yes')
    # Conditional responses explicitly preserve Range / Content-Range support
    # required by native voice/video players when seeking.
    return send_from_directory(
        upload_folder,
        media.stored_name,
        conditional=not download,
        as_attachment=download,
        download_name=media.original_name if download else None,
    )
