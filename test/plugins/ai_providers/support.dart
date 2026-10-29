// What the AI providers' plugin tests share (docs/AI_PROVIDERS.md, "Tests"): a provider page over settings of the
// test's own and a provider that answers what the test says, so a setup's check and a page's list never reach a
// network.
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/assistant/provider.dart';
import 'package:ghost_md/assistant/provider_page.dart';
import 'package:ghost_md/assistant/provider_settings.dart';
import 'package:ghost_md/assistant/provider_setup.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';

/// A provider of the test's own: [answer] for a check, [listed] for the models.
class FakeProvider implements AiProvider {
  FakeProvider(this.test);
  final ProviderTest test;

  @override
  AiCall stream(Map<String, Object?> body) => throw UnimplementedError();

  @override
  Future<AiError?> check() async {
    test.checked += 1;
    return test.answer;
  }

  @override
  Future<List<AiModelInfo>> models() async => test.listed;
}

class ProviderTest {
  ProviderTest(AiProviderPage base) {
    settings = AiProviderSettings(MemorySecureStore(), prefix: base.settings.prefix, name: base.settings.name, keyOptional: base.settings.keyOptional, needsBase: base.settings.needsBase, fallbackModels: base.settings.fallbackModels, ratesFor: base.settings.ratesFor);
    page = base.copyWith(settings: settings, client: (settings, {key}) {
      keys.add(key ?? settings.key);
      return FakeProvider(this);
    });
  }

  late final AiProviderSettings settings;
  late final AiProviderPage page;
  AiError? answer;
  List<AiModelInfo> listed = const [AiModelInfo('model-one', name: 'Model One'), AiModelInfo('model-two', name: 'Model Two')];
  int checked = 0;
  final List<String?> keys = [];

  PluginSetup setup() => providerSetup(page);
}

