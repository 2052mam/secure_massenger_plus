class ApiConstants {
  // ===== تغییر این مقدار برای اتصال به سرور واقعی =====
  // مثال پروداکشن:
  // static const String baseUrl = 'https://api.yourdomain.com/api/v1';
  // برای امولاتور اندروید:
  // static const String baseUrl = 'http://10.229.207.93:5000/api/v1';
  static const String baseUrl = 'https://massenger.reservira.ir/api/v1';
  // برای دستگاه واقعی روی همان شبکه:
  // static const String baseUrl = 'http://192.168.1.x:5000/api/v1';

  static const String authRegister = '/auth/register';
  static const String authVerify2fa = '/auth/verify-2fa'; // legacy only
  static const String authRequestPhoneCode = '/auth/request-phone-code';
  static const String authResendPhoneCode = '/auth/resend-phone-code';
  static const String authVerifyPhone = '/auth/verify-phone';
  static const String authVerifyLogin2fa = '/auth/verify-login-2fa';
  static const String authLogin = '/auth/login'; // legacy accounts only
  static const String authLogout = '/auth/logout';
  static const String authRefresh = '/auth/refresh';

  static const String usersMe = '/users/me';
  static const String usersSearch = '/users/search';

  static const String chats = '/chats';
  static const String messages = '/messages';
  static const String messagesPoll = '/messages/poll';
  static const String mediaUpload = '/media/upload';

  static const int pollingIntervalSeconds = 3;
}
