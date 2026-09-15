import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

class ChatLabels {
  ChatLabels.of(BuildContext context)
    : isFa = Localizations.localeOf(context).languageCode == 'fa';

  final bool isFa;
  String get online => isFa ? 'آنلاین' : 'Online';
  String get lastSeenHidden =>
      isFa ? 'آخرین بازدید پنهان است' : 'Last seen hidden';
  String get profile => isFa ? 'مشاهده پروفایل' : 'View profile';
  String get group => isFa ? 'گروه' : 'Group';
  String get channel => isFa ? 'کانال' : 'Channel';
  String get saved => isFa ? 'پیام‌های ذخیره‌شده' : 'Saved Messages';
  String get reply => isFa ? 'پاسخ' : 'Reply';
  String get forward => isFa ? 'فوروارد' : 'Forward';
  String get copy => isFa ? 'کپی متن' : 'Copy text';
  String get copied => isFa ? 'متن کپی شد' : 'Text copied';
  String get copyFailed => isFa ? 'کپی متن ناموفق بود' : 'Could not copy text';
  String get deleteForMe => isFa ? 'حذف برای من' : 'Delete for me';
  String get deleteForAll => isFa ? 'حذف برای همه' : 'Delete for everyone';
  String get invite => isFa ? 'لینک دعوت' : 'Invite link';
  String get copyLink => isFa ? 'کپی لینک' : 'Copy link';
  String get linkCopied => isFa ? 'لینک کپی شد' : 'Link copied';
  String get joinGroup => isFa ? 'عضویت در گروه' : 'Join group';
  String get joinChannel => isFa ? 'عضویت در کانال' : 'Join channel';
  String get cancel => isFa ? 'لغو' : 'Cancel';
  String get close => isFa ? 'بستن' : 'Close';
  String get inviteUnavailable => isFa
      ? 'لینک دعوت نامعتبر است یا اجازه عضویت ندارید'
      : 'This invite is invalid, unavailable, or you cannot join this chat';
  String get inviteFailed => isFa
      ? 'باز کردن لینک ناموفق بود. دوباره تلاش کنید.'
      : 'Could not open the invite. Please try again.';
  String get chatUnavailable =>
      isFa ? 'این چت دیگر در دسترس نیست' : 'This chat is no longer available';

  // ----- Archive ------------------------------------------------------
  String get archive => isFa ? 'آرشیو' : 'Archive';
  String get archivedChats => isFa ? 'چت‌های آرشیوشده' : 'Archived chats';
  String get archiveChat => isFa ? 'آرشیو کردن' : 'Archive';
  String get unarchiveChat => isFa ? 'خروج از آرشیو' : 'Unarchive';
  String get archiveEmpty =>
      isFa ? 'آرشیو خالی است' : 'No archived chats yet';
  String get archiveLocked => isFa ? 'آرشیو قفل است' : 'Archive is locked';
  String get archiveLock => isFa ? 'قفل آرشیو' : 'Archive lock';
  String get archivePinTitle =>
      isFa ? 'رمز چهاررقمی آرشیو' : 'Four digit archive password';
  String get archivePinEnter =>
      isFa ? 'رمز آرشیو را وارد کنید' : 'Enter the archive password';
  String get archivePinNew =>
      isFa ? 'رمز جدید چهاررقمی' : 'New four digit password';
  String get archivePinRepeat =>
      isFa ? 'تکرار رمز جدید' : 'Repeat the new password';
  String get archivePinCurrent =>
      isFa ? 'رمز فعلی' : 'Current password';
  String get archivePinMismatch =>
      isFa ? 'رمزها یکسان نیستند' : 'The passwords do not match';
  String get archivePinInvalid =>
      isFa ? 'رمز باید دقیقاً ۴ رقم باشد' : 'The password must be exactly 4 digits';
  String get archivePinSet => isFa ? 'رمز آرشیو ذخیره شد' : 'Archive password saved';
  String get archivePinRemoved =>
      isFa ? 'رمز آرشیو حذف شد' : 'Archive password removed';
  String get archivePinOff => isFa ? 'بدون رمز' : 'No password';
  String get archivePinOn => isFa ? 'فعال است' : 'Enabled';
  String get archivePinRemove => isFa ? 'حذف رمز آرشیو' : 'Remove archive password';
  String get archivePinChange => isFa ? 'تغییر رمز آرشیو' : 'Change archive password';
  String get archivePinCreate => isFa ? 'تنظیم رمز آرشیو' : 'Set an archive password';
  String get archiveLockHint => isFa
      ? 'با فعال کردن رمز، برای باز کردن آرشیو باید رمز چهاررقمی وارد شود.'
      : 'When enabled, opening the archive requires the four digit password.';
  String get unlock => isFa ? 'باز کردن' : 'Unlock';

  // ----- Pinning ------------------------------------------------------
  String get pinChat => isFa ? 'سنجاق به بالای فهرست' : 'Pin to top';
  String get unpinChat => isFa ? 'برداشتن سنجاق' : 'Unpin';
  String get pinMessage => isFa ? 'سنجاق کردن پیام' : 'Pin message';
  String get unpinMessage => isFa ? 'برداشتن سنجاق پیام' : 'Unpin message';
  String get pinnedMessages => isFa ? 'پیام‌های سنجاق‌شده' : 'Pinned messages';
  String get unpinAll => isFa ? 'برداشتن همه سنجاق‌ها' : 'Unpin all messages';
  String get noPinnedMessages =>
      isFa ? 'پیام سنجاق‌شده‌ای نیست' : 'No pinned messages';
  String pinnedCount(int count) => isFa
      ? '$count پیام سنجاق‌شده'
      : '$count pinned ${count == 1 ? 'message' : 'messages'}';

  // ----- Folders ------------------------------------------------------
  String get folderAll => isFa ? 'همه' : 'All';
  String get folderPersonal => isFa ? 'شخصی' : 'Personal';
  String get folders => isFa ? 'پوشه‌ها' : 'Folders';
  String get newFolder => isFa ? 'پوشه جدید' : 'New folder';
  String get editFolders => isFa ? 'ویرایش پوشه‌ها' : 'Edit folders';
  String get editFolder => isFa ? 'ویرایش پوشه' : 'Edit folder';
  String get folderName => isFa ? 'نام پوشه' : 'Folder name';
  String get folderNameRequired =>
      isFa ? 'نام پوشه الزامی است' : 'A folder name is required';
  String get folderTypes => isFa ? 'نوع گفتگوها' : 'Chat types';
  String get folderIncludePrivate => isFa ? 'چت‌های شخصی' : 'Private chats';
  String get folderIncludeGroups => isFa ? 'گروه‌ها' : 'Groups';
  String get folderIncludeChannels => isFa ? 'کانال‌ها' : 'Channels';
  String get folderIncludeArchived =>
      isFa ? 'نمایش چت‌های آرشیوشده' : 'Include archived chats';
  String get folderChats => isFa ? 'چت‌های انتخاب‌شده' : 'Selected chats';
  String get folderEmpty => isFa ? 'این پوشه خالی است' : 'This folder is empty';
  String get folderDelete => isFa ? 'حذف پوشه' : 'Delete folder';
  String get folderRules => isFa
      ? 'می‌توانید نوع گفتگوها را انتخاب کنید یا چت‌ها را تک‌به‌تک اضافه کنید.'
      : 'Choose chat types, add individual chats, or mix both.';

  // ----- Misc ---------------------------------------------------------
  String get mute => isFa ? 'بی‌صدا' : 'Mute';
  String get unmute => isFa ? 'باصدا' : 'Unmute';
  String get delete => isFa ? 'حذف' : 'Delete';
  String get save => isFa ? 'ذخیره' : 'Save';
  String get recentSearches => isFa ? 'جستجوهای اخیر' : 'Recent searches';
  String get clearAll => isFa ? 'پاک کردن همه' : 'Clear all';
  String get profilePhotos => isFa ? 'عکس‌های پروفایل' : 'Profile photos';
  String get addPhoto => isFa ? 'افزودن عکس' : 'Add photo';
  String get setMainPhoto => isFa ? 'انتخاب به‌عنوان عکس اصلی' : 'Set as main photo';
  String get deletePhoto => isFa ? 'حذف عکس' : 'Delete photo';
  String get mainPhoto => isFa ? 'عکس اصلی' : 'Main photo';
  String get noPhotos => isFa ? 'هنوز عکسی ندارید' : 'No photos yet';
  String photoCounter(int index, int total) =>
      isFa ? '$index از $total' : '$index of $total';

  String members(int count, {bool subscribers = false}) => isFa
      ? '$count ${subscribers ? 'مشترک' : 'عضو'}'
      : '$count ${subscribers ? (count == 1 ? 'subscriber' : 'subscribers') : (count == 1 ? 'member' : 'members')}';

  String lastSeen(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final time = DateFormat('HH:mm').format(local);
    final String when;
    if (day == today) {
      when = isFa ? 'امروز ساعت $time' : 'today at $time';
    } else if (day == DateTime(now.year, now.month, now.day - 1)) {
      when = isFa ? 'دیروز ساعت $time' : 'yesterday at $time';
    } else {
      when = DateFormat('yyyy/MM/dd HH:mm').format(local);
    }
    return isFa ? 'آخرین بازدید $when' : 'Last seen $when';
  }
}
