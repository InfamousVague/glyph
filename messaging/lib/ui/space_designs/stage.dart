import 'package:flutter/widgets.dart';

import 'space_design.dart';

/// A space's call in the stage design (lib/ui/space_designs/space_design.dart: SpaceDesign.stage). Not drawn yet.
class StageCall extends StatelessWidget {
  const StageCall({super.key, required this.call});
  final SpaceCall call;

  @override
  Widget build(BuildContext context) => SpaceDesignStub(call: call, name: 'stage');
}
