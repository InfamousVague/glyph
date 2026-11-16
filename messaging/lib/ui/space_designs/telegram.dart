import 'package:flutter/widgets.dart';

import 'space_design.dart';

/// A space's call in the telegram design (lib/ui/space_designs/space_design.dart: SpaceDesign.telegram). Not drawn yet.
class TelegramCall extends StatelessWidget {
  const TelegramCall({super.key, required this.call});
  final SpaceCall call;

  @override
  Widget build(BuildContext context) => SpaceDesignStub(call: call, name: 'telegram');
}
