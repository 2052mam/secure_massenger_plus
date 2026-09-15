from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from dotenv import load_dotenv
import os

load_dotenv()

db = SQLAlchemy()
migrate = Migrate()
jwt = JWTManager()

def create_app():
    app = Flask(__name__)

    app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'dev-secret-change-me')
    app.config['JWT_SECRET_KEY'] = os.getenv('JWT_SECRET_KEY', 'jwt-secret-change-me')
    app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {
        'pool_pre_ping': True,
        'pool_recycle': 280,
    }
    app.config['MAX_CONTENT_LENGTH'] = int(os.getenv('MAX_CONTENT_LENGTH', 50 * 1024 * 1024))
    app.config['UPLOAD_FOLDER'] = os.getenv('UPLOAD_FOLDER', 'uploads')
    app.config['ADMIN_SECRET_PATH'] = os.getenv('ADMIN_SECRET_PATH', 'sm-admin-x9k2p7')
    app.config['MAX_ACCOUNTS_PER_DEVICE'] = int(os.getenv('MAX_ACCOUNTS_PER_DEVICE', 3))

    # SMS.ir credentials deliberately stay server-side. The Flutter client
    # talks only to this API; it never contains or sees a provider API key.
    app.config['SMS_DELIVERY_MODE'] = os.getenv('SMS_DELIVERY_MODE', 'sms_ir')
    app.config['SMS_IR_API_KEY'] = os.getenv('SMS_IR_API_KEY')
    app.config['SMS_IR_TEMPLATE_ID'] = os.getenv('SMS_IR_TEMPLATE_ID')
    app.config['SMS_IR_CODE_PARAMETER'] = os.getenv('SMS_IR_CODE_PARAMETER', 'CODE')
    app.config['SMS_IR_TEMPLATE_PARAMETERS'] = os.getenv('SMS_IR_TEMPLATE_PARAMETERS', '')
    app.config['SMS_IR_TIMEOUT_SECONDS'] = int(os.getenv('SMS_IR_TIMEOUT_SECONDS', 10))
    app.config['PHONE_CODE_TTL_SECONDS'] = int(os.getenv('PHONE_CODE_TTL_SECONDS', 600))
    app.config['PHONE_CODE_RESEND_SECONDS'] = int(os.getenv('PHONE_CODE_RESEND_SECONDS', 60))
    app.config['PHONE_CODE_MAX_ATTEMPTS'] = int(os.getenv('PHONE_CODE_MAX_ATTEMPTS', 5))
    app.config['PHONE_CODE_MAX_PER_HOUR'] = int(os.getenv('PHONE_CODE_MAX_PER_HOUR', 5))
    app.config['PHONE_CODE_MAX_PER_IP_HOUR'] = int(os.getenv('PHONE_CODE_MAX_PER_IP_HOUR', 20))

    os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)
    CORS(app, resources={r"/api/*": {"origins": "*"}})

    from app.api.auth import auth_bp
    from app.api.users import users_bp
    from app.api.chats import chats_bp
    from app.api.messages import messages_bp
    from app.api.media import media_bp
    from app.api.admin_api import admin_api_bp
    from app.api.reports import reports_bp
    from app.api.reactions import reactions_bp
    from app.api.stickers import stickers_bp
    from app.api.gifs import gifs_bp
    from app.api.devices import devices_bp
    from app.api.stories import stories_bp
    from app.admin.routes import admin_web_bp

    app.register_blueprint(auth_bp, url_prefix='/api/v1/auth')
    app.register_blueprint(users_bp, url_prefix='/api/v1/users')
    app.register_blueprint(chats_bp, url_prefix='/api/v1/chats')
    app.register_blueprint(messages_bp, url_prefix='/api/v1/messages')
    app.register_blueprint(media_bp, url_prefix='/api/v1/media')
    app.register_blueprint(admin_api_bp, url_prefix='/api/v1/admin')
    app.register_blueprint(reports_bp, url_prefix='/api/v1/reports')
    app.register_blueprint(reactions_bp, url_prefix='/api/v1/reactions')
    app.register_blueprint(stickers_bp, url_prefix='/api/v1/stickers')
    app.register_blueprint(gifs_bp, url_prefix='/api/v1/gifs')
    app.register_blueprint(devices_bp, url_prefix='/api/v1/devices')
    app.register_blueprint(stories_bp, url_prefix='/api/v1/stories')
    try:
        from app.api.notifications import notifications_bp
        app.register_blueprint(notifications_bp, url_prefix='/api/v1/notifications')
    except ImportError:
        # Older checkouts without the notifications module keep working.
        pass
    app.register_blueprint(admin_web_bp)

    # The Flutter client only understands JSON. A single HTML error page
    # (Flask debug page, Passenger 500, proxy gateway error) used to crash
    # JSON parsing on the phone with a red "<!DOCTYPE ..." message and left
    # the chat screen unloadable. Every API error is JSON from here on.
    from flask import jsonify, request
    from werkzeug.exceptions import HTTPException

    @app.errorhandler(404)
    def _json_404(error):
        if request.path.startswith('/api/'):
            return jsonify({'error': 'یافت نشد'}), 404
        return error

    @app.errorhandler(405)
    def _json_405(error):
        if request.path.startswith('/api/'):
            return jsonify({'error': 'متد مجاز نیست'}), 405
        return error

    @app.errorhandler(413)
    def _json_413(error):
        if request.path.startswith('/api/'):
            return jsonify({'error': 'حجم فایل بیش از حد مجاز است'}), 413
        return error

    @app.errorhandler(HTTPException)
    def _json_http_exception(error):
        if request.path.startswith('/api/'):
            message = error.description if isinstance(
                error.description, str) else 'خطای سرور'
            # Never leak raw HTML descriptions to the mobile client.
            if '<' in message and '>' in message:
                message = 'خطای سرور. لطفاً دوباره تلاش کنید.'
            return jsonify({'error': message}), error.code or 500
        raise error

    @app.errorhandler(Exception)
    def _json_unexpected(error):
        if request.path.startswith('/api/'):
            try:
                db.session.rollback()
            except Exception:
                pass
            app.logger.exception('Unhandled API error on %s', request.path)
            return jsonify(
                {'error': 'خطای موقت سرور. لطفاً دوباره تلاش کنید.'}), 500
        raise error

    # JWT errors must also be JSON (device termination returns 401 below).
    @jwt.expired_token_loader
    def _jwt_expired(_header, _payload):
        return jsonify({'error': 'نشست منقضی شده است', 'code': 'token_expired'}), 401

    @jwt.invalid_token_loader
    def _jwt_invalid(reason):
        return jsonify(
            {'error': f'نشست نامعتبر است: {reason}', 'code': 'token_invalid'}), 401

    @jwt.unauthorized_loader
    def _jwt_missing(reason):
        return jsonify(
            {'error': f'احراز هویت لازم است: {reason}', 'code': 'token_missing'}), 401

    @jwt.revoked_token_loader
    def _jwt_revoked(_header, payload):
        return jsonify({
            'error': 'این دستگاه از حساب خارج شده است. لطفاً دوباره وارد شوید.',
            'code': 'device_terminated',
        }), 401

    @jwt.token_in_blocklist_loader
    def _jwt_blocklist(_header, payload):
        # Terminated devices lose access immediately, even though the JWT
        # itself is still cryptographically valid and unexpired.
        try:
            from app.models.user import UserDevice, UserSession
            device_id = payload.get('device_id')
            user_id = payload.get('sub')
            if device_id:
                device = UserDevice.query.filter_by(
                    id=device_id, user_id=user_id,
                ).first()
                # Unknown device ids belong to legacy rows; only an explicit
                # soft-delete / deactivation revokes the token.
                if device is not None and (
                        device.is_deleted or not device.is_active):
                    return True
            if payload.get('type') == 'refresh' and device_id:
                session = UserSession.query.filter_by(
                    device_id=device_id, user_id=user_id, is_active=True,
                ).first()
                if session is None:
                    return True
        except Exception:
            # A blocklist lookup failure must fail open; the request itself
            # still requires a valid signature and expiry.
            return False
        return False

    @app.cli.command('upgrade-chat-schema')
    def upgrade_chat_schema():
        from app.services.schema_upgrade import upgrade_schema
        upgrade_schema()
        print('Chat/privacy schema is up to date.')

    @app.route('/health')
    def health():
        return {'status': 'ok', 'polling': True}, 200

    return app
