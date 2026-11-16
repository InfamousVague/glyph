import 'package:flutter/widgets.dart';

import 'space_design.dart';

/// A space's call in the discord design (lib/ui/space_designs/space_design.dart: SpaceDesign.discord). Not drawn yet.
class DiscordCall extends StatelessWidget {
  const DiscordCall({super.key, required this.call});
  final SpaceCall call;

  @override
  Widget build(BuildContext context) => SpaceDesignStub(call: call, name: 'discord');
}
