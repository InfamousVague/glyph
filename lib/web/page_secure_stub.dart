/// page_secure.dart's on a device, where nothing asks for it: `deviceSecureStore` hands over only in a browser.
library;

import '../account/device_keys.dart' show SecureStore;

SecureStore pageSecureStore() => throw UnsupportedError('The page\'s storage is only in the web build.');
