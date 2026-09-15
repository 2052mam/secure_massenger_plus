import 'package:flutter/widgets.dart';

/// Localized strings for the new media surfaces (including RTL chat layouts).
class MediaLabels {
  final bool isFa;
  MediaLabels.of(BuildContext context)
    : isFa = Localizations.localeOf(context).languageCode == 'fa';

  String get photo => isFa ? 'عکس' : 'Photo';
  String get video => isFa ? 'ویدیو' : 'Video';
  String get voice => isFa ? 'پیام صوتی' : 'Voice message';
  String get file => isFa ? 'فایل' : 'File';
  String get message => isFa ? 'پیام' : 'Message';
  String get you => isFa ? 'شما' : 'You';
  String get unknownSender => isFa ? 'فرستنده' : 'Sender';
  String get unavailable => isFa ? 'پیام در دسترس نیست' : 'Message unavailable';
  String get reply => isFa ? 'پاسخ به' : 'Reply to';
  String get cancelReply => isFa ? 'لغو پاسخ' : 'Cancel reply';
  String get close => isFa ? 'بستن' : 'Close';
  String get retry => isFa ? 'تلاش مجدد' : 'Retry';
  String get loadError =>
      isFa ? 'بارگذاری رسانه ناموفق بود' : 'Could not load media';
  String get play => isFa ? 'پخش' : 'Play';
  String get pause => isFa ? 'توقف' : 'Pause';
  String get replay => isFa ? 'پخش دوباره' : 'Replay';
  String get rewind => isFa ? '۱۰ ثانیه عقب' : 'Rewind 10 seconds';
  String get forward => isFa ? '۱۰ ثانیه جلو' : 'Forward 10 seconds';
  String get speed => isFa ? 'سرعت پخش' : 'Playback speed';
  String get seek => isFa ? 'موقعیت پخش' : 'Playback position';
  String get fullscreen => isFa ? 'تمام صفحه' : 'Full screen';
  String get exitFullscreen => isFa ? 'خروج از تمام صفحه' : 'Exit full screen';
  String get mute => isFa ? 'بی‌صدا' : 'Mute';
  String get unmute => isFa ? 'با صدا' : 'Unmute';
  String get viewOnce => isFa ? 'عکس یک‌بارمصرف' : 'View-once photo';
  String get tapToOpen => isFa ? 'برای مشاهده بزنید' : 'Tap to open';
  String get viewed => isFa ? 'عکس مشاهده شد' : 'Photo viewed';
  String get sentOnce =>
      isFa ? 'فقط گیرنده می‌تواند باز کند' : 'Only the recipient can open';
  String get disappears => isFa
      ? 'پس از بستن، دوباره قابل مشاهده نیست'
      : 'Once closed, this photo cannot be opened again';
  String get expired =>
      isFa ? 'عکس دیگر در دسترس نیست' : 'This photo is no longer available';
  String get latest =>
      isFa ? 'بازگشت به آخرین پیام‌ها' : 'Back to latest messages';
  String get earlier => isFa ? 'پیام‌های قدیمی‌تر' : 'Earlier messages';

  String type(String type) => switch (type) {
    'image' => photo,
    'video' => video,
    'voice' || 'audio' => voice,
    'file' || 'document' => file,
    _ => message,
  };
}
