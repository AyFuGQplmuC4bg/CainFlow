import 'package:flutter/material.dart';
import 'package:signals/signals.dart';

import '../core/storage/local_kv_store.dart';
import '../core/storage/mmkv_local_kv_store.dart';

const _kLocaleKey = 'app_locale';

/// Persisted locale override. `null` means follow the system locale.
final Signal<Locale?> localeSignal = _loadLocale();

Signal<Locale?> _loadLocale() {
  final sig = signal<Locale?>(null);
  try {
    final store = MmkvLocalKvStore();
    final saved = store.getString(_kLocaleKey);
    if (saved != null && saved.isNotEmpty) {
      sig.value = Locale(saved);
    }
  } catch (_) {}
  return sig;
}

/// Persist and update the locale override. Pass `null` to follow system.
void setLocale(Locale? locale, {LocalKvStore? store}) {
  localeSignal.value = locale;
  try {
    final kv = store ?? MmkvLocalKvStore();
    if (locale == null) {
      kv.remove(_kLocaleKey);
    } else {
      kv.setString(_kLocaleKey, locale.languageCode);
    }
  } catch (_) {}
}
