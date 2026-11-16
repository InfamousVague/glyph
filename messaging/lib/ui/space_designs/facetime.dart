import 'package:flutter/widgets.dart';

import 'space_design.dart';

/// A space's call in the facetime design (lib/ui/space_designs/space_design.dart: SpaceDesign.facetime). Not drawn yet.
class FaceTimeCall extends StatelessWidget {
  const FaceTimeCall({super.key, required this.call});
  final SpaceCall call;

  @override
  Widget build(BuildContext context) => SpaceDesignStub(call: call, name: 'facetime');
}
