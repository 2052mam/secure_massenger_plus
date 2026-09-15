# ورود با شماره موبایل و SMS.ir

## جریان کار

1. کاربر در ثبت‌نام نام، ایمیل، رمز عبور و شماره موبایل را وارد می‌کند.
2. سرور شماره را به E.164 (برای نمونه `+989121234567`) تبدیل می‌کند و با
   `POST https://api.sms.ir/v1/send/verify` یک کد شش‌رقمی ارسال می‌کند.
3. تا زمانی که کد درست وارد نشود، حساب غیرفعال است. کد هرگز در پاسخ API،
   کلاینت، یا audit log ذخیره نمی‌شود؛ فقط HMAC آن در جدول
   `phone_verifications` با انقضای پیش‌فرض ۱۰ دقیقه نگهداری می‌شود.
4. ورودهای بعدی با شماره موبایل و پیامک انجام می‌شوند. اگر کاربر از Settings
   گزینه Google Authenticator را فعال کرده باشد، پس از SMS یک کد TOTP نیز لازم
   است.
5. ورود ایمیل/رمز تنها برای حساب‌های قدیمی که هنوز شماره تأییدشده ندارند حفظ
   شده است، تا به‌روزرسانی هیچ حسابی را قفل نکند.

## تنظیم SMS.ir

کلید SMS.ir فقط باید روی backend قرار بگیرد. آن را در Flutter، Android manifest
یا Git قرار ندهید.

```bash
cd backend
cp .env.example .env
```

در `.env` مقادیر زیر را با مقادیر پنل SMS.ir جایگزین کنید:

```dotenv
SMS_DELIVERY_MODE=sms_ir
SMS_IR_API_KEY=your-rotated-sms-ir-key
SMS_IR_TEMPLATE_ID=123456
SMS_IR_CODE_PARAMETER=CODE
```

نام پارامتر باید دقیقاً با نامی که در template SMS.ir ساخته‌اید یکی باشد. برای
templateهای چندپارامتری به‌جای `SMS_IR_CODE_PARAMETER` مقدار JSON زیر را تنظیم
کنید (نام‌ها نمونه‌اند):

```dotenv
SMS_IR_TEMPLATE_PARAMETERS={"CODE":"{code}","APP":"SecureMessenger"}
```

`{code}` و `{mobile}` هنگام ارسال جایگزین می‌شوند. بدنه درخواست نهایی به‌صورت
`mobile`، `templateId` و آرایه `parameters` به endpoint رسمی
`/v1/send/verify` ارسال می‌شود.

### آزمایش محلی

برای تست UI بدون ارسال پیامک واقعی می‌توانید موقتاً این مقدار را در `.env`
قرار دهید:

```dotenv
SMS_DELIVERY_MODE=console
```

کد فقط در log **سرور** چاپ می‌شود و از API به اپ برنمی‌گردد. برای ارسال واقعی
حتی هنگامی که API محلی شما HTTP است، ارتباط backend با `api.sms.ir` همچنان HTTPS
است. برای انتشار، `baseUrl` Flutter را به HTTPS تغییر دهید و
`android:usesCleartextTraffic="true"` را حذف/false کنید.

## مهاجرت دیتابیس

پس از backup و توقف workerها، backend جدید را deploy کرده و یک‌بار اجرا کنید:

```bash
cd backend
python -m flask --app run:app upgrade-chat-schema
```

این دستور فقط `mobile_number`، `mobile_verified_at`، ایندکس یکتا، و جدول
`phone_verifications` را افزایشی اضافه می‌کند؛ داده یا حساب‌های قبلی را حذف
نمی‌کند. ابتدا نسخه backend و migration را منتشر کنید، سپس Flutter را منتشر
کنید تا کاربر قدیمی در صفحه ورود ناگهان به جریان جدید فرستاده نشود.

## محدودیت‌های امنیتی

- کدها شش‌رقمی، یک‌بارمصرف و ۱۰ دقیقه‌ای هستند.
- کد جدید کد قبلی همان جریان را باطل می‌کند.
- پیش‌فرض‌ها: حداقل ۶۰ ثانیه بین ارسال مجدد، ۵ درخواست شماره در ساعت، ۲۰
  درخواست IP در ساعت، و ۵ تلاش ناموفق.
- پاسخ درخواست ورود برای شماره ثبت‌نشده نیز `202` است تا شماره‌های دارای حساب
  قابل شناسایی نباشند.
- Google Authenticator در Settings فقط پس از اسکن QR و وارد کردن یک TOTP فعال
  می‌شود و با یک TOTP معتبر قابل غیرفعال‌سازی است.
