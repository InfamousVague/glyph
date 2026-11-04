/// The image model Lovart is asked to use (Matt, 2026-11-04: "add the ability to change the image generation model on
/// the lovart plugin"). Unchosen, Lovart's agent picks one as it always has.
///
/// Sent as the chat's `tool_config.prefer_tool_categories` `{"IMAGE": [<tool>]}`, which the Lovart skill calls "the
/// same as frontend's model selector" (github.com/lovartai/lovart-skill, SKILL.md "Specifying Models", agent_skill.py
/// `send`, read 2026-11-04). It is a preference: the agent may still choose another, and a premium model can come back
/// asking for approval in Lovart (`pending_confirmation`), which the plugin never gives. The names are the skill's
/// table, the quality levels of one model left to its Auto; re-read it when Lovart adds or drops one.
library;

import '../../core/metrics.dart' show trackPlugin;
import '../types.dart';
import 'manifest.dart' show host, lovartModelKey;

class LovartModel {
  const LovartModel(this.id, this.name, this.about);

  /// Lovart's tool name, as the skill lists it.
  final String id;
  final String name;

  /// A line under its name.
  final String about;
}

const List<LovartModel> lovartModels = [
  LovartModel('generate_image_nano_banana_pro', 'Nano Banana Pro', 'Google’s best: true to the prompt, good with real places'),
  LovartModel('generate_image_nano_banana_2_1', 'Nano Banana 2.1', 'Google, newer and quick'),
  LovartModel('generate_image_nano_banana_2', 'Nano Banana 2', 'Google, quick'),
  LovartModel('generate_image_nano_banana_2_lite', 'Nano Banana 2 Lite', 'Google, the lightest'),
  LovartModel('generate_image_gpt_image_2_5_flare', 'GPT Image 2.5 Flare', 'OpenAI, newest'),
  LovartModel('generate_image_gpt_image_2_5_sunburst', 'GPT Image 2.5 Sunburst', 'OpenAI, newest'),
  LovartModel('generate_image_gpt_image_2', 'GPT Image 2', 'OpenAI'),
  LovartModel('generate_image_gpt_image_1_5', 'GPT Image 1.5', 'OpenAI, older'),
  LovartModel('generate_image_midjourney', 'Midjourney', 'Painterly and atmospheric'),
  LovartModel('generate_image_seedream_v5_pro', 'Seedream 5.0 Pro', 'ByteDance, detailed'),
  LovartModel('generate_image_seedream_v5', 'Seedream 5.0 Lite', 'ByteDance, quick'),
  LovartModel('generate_image_seedream_v4_5', 'Seedream 4.5', 'ByteDance'),
  LovartModel('generate_image_flux_2_max', 'Flux.2 Max', 'Black Forest Labs, photographic'),
  LovartModel('generate_image_flux_2_pro', 'Flux.2 Pro', 'Black Forest Labs'),
  LovartModel('generate_image_ideogram_v4', 'Ideogram 4', 'Good with lettering and design'),
  LovartModel('generate_image_luma_uni_1_max', 'Luma uni-1-max', 'Luma'),
  LovartModel('generate_image_luma_uni_1', 'Luma uni-1', 'Luma'),
  LovartModel('generate_image_qwen_image3_pro', 'Qwen Image3 Pro', 'Alibaba'),
  LovartModel('generate_image_qwen_image3', 'Qwen Image3', 'Alibaba'),
];

/// The model chosen, or null for Lovart's own choice (also when the one kept is no longer listed).
LovartModel? lovartModel([PluginHost? via]) {
  final Object? kept = (via ?? host).storage.get<Object?>(lovartModelKey, null);
  return lovartModels.where((model) => model.id == kept).firstOrNull;
}

/// Chooses [model], on every device; null is Lovart's own choice again.
void setLovartModel(LovartModel? model, [PluginHost? via]) {
  final on = via ?? host;
  model == null ? on.storage.remove(lovartModelKey) : on.storage.set(lovartModelKey, model.id);
  // The anonymous usage stats (lib/core/metrics.dart): the tool id from the list above, or `auto` for Lovart's own.
  trackPlugin('lovart', 'model_chosen', choice: model?.id ?? 'auto');
}

/// The chat's `tool_config` for the model chosen, or null to send none.
Map<String, Object?>? lovartToolConfig([PluginHost? via]) {
  final model = lovartModel(via);
  return model == null
      ? null
      : {
          'prefer_tool_categories': {
            'IMAGE': [model.id],
          },
        };
}
