/// App rules shown during registration (scroll-to-accept popup) and in Settings.
class TermsService {
  static const int currentVersion = 1;

  static const String rulesFa = '''
قوانین استفاده از پیام‌رسان امن

۱. احترام به کاربران
- توهین، تهدید، آزار و اذیت و انتشار محتوای نفرت‌پراکن ممنوع است.
- انتشار اطلاعات خصوصی دیگران (شماره، آدرس، عکس خصوصی) بدون رضایت ممنوع است.

۲. محتوای ممنوع
- محتوای غیراخلاقی، خشونت‌آمیز، تروریستی و غیرقانونی ممنوع است.
- انتشار بدافزار، لینک فیشینگ و هرگونه کلاهبرداری ممنوع است.
- نقض کپی‌رایت و انتشار آثار دیگران بدون اجازه ممنوع است.

۳. امنیت حساب
- رمز عبور و کد تایید دوعاملی (2FA) خود را در اختیار دیگران قرار ندهید.
- در صورت مشاهده ورود مشکوک، فوراً رمز را تغییر دهید و نشست‌ها را بررسی کنید.

۴. گروه‌ها و کانال‌ها
- مدیران مسئول محتوای گروه/کانال خود هستند.
- فوروارد، تبلیغات اسپم و عضوگیری اجباری بدون رضایت ممنوع است.
- کانال‌های اسپانسرشده توسط مدیر کل برنامه مشخص می‌شوند.

۵. حریم خصوصی
- پیام‌های امن (حالت امنیتی) و پیام‌های رمزدار با رمز شما محافظت می‌شوند؛ رمز را فراموش نکنید چون قابل بازیابی نیست.
- عکس‌های یک‌بارمصرف پس از مشاهده از دسترس خارج می‌شوند.

۶. برخورد با تخلف
- گزارش کاربران بررسی می‌شود و در صورت تخلف، حساب محدود، تعلیق یا حذف می‌شود.
- در موارد قانونی، اطلاعات لازم طبق قوانین در اختیار مراجع ذی‌صلاح قرار می‌گیرد.

با پذیرش این قوانین، شما متعهد به رعایت آن‌ها می‌شوید.
نسخه قوانین: ۱
''';

  static const String rulesEn = '''
Secure Messenger Terms of Use

1. Respect other users
- Insults, threats, harassment and hate speech are prohibited.
- Sharing others' private data (phone, address, private photos) without consent is prohibited.

2. Prohibited content
- Immoral, violent, terrorist and illegal content is prohibited.
- Malware, phishing links and any fraud are prohibited.
- Copyright infringement is prohibited.

3. Account security
- Never share your password or 2FA code with anyone.
- If you notice a suspicious login, change your password immediately and review sessions.

4. Groups and channels
- Admins are responsible for their group/channel content.
- Spam forwarding, advertising spam and forced invites are prohibited.
- Sponsored channels are marked by the general app admin.

5. Privacy
- Secure-mode and password-encrypted messages are protected by your password; if you forget it, content cannot be recovered.
- View-once photos become unavailable after viewing.

6. Violations
- User reports are reviewed; violating accounts may be limited, suspended or removed.
- Where required by law, necessary data may be shared with competent authorities.

By accepting these rules you agree to follow them.
Terms version: 1
''';

  static String rulesFor(String languageCode) =>
      languageCode == 'fa' ? rulesFa : rulesEn;
}
