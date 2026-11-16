import 'package:flutter/widgets.dart';

import 'space_design.dart';

/// A space's call in the zoom design (lib/ui/space_designs/space_design.dart: SpaceDesign.zoom). Not drawn yet.
class ZoomCall extends StatelessWidget {
  const ZoomCall({super.key, required this.call});
  final SpaceCall call;

  @override
  Widget build(BuildContext context) => SpaceDesignStub(call: call, name: 'zoom');
}
