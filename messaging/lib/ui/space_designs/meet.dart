import 'package:flutter/widgets.dart';

import 'space_design.dart';

/// A space's call in the meet design (lib/ui/space_designs/space_design.dart: SpaceDesign.meet). Not drawn yet.
class MeetCall extends StatelessWidget {
  const MeetCall({super.key, required this.call});
  final SpaceCall call;

  @override
  Widget build(BuildContext context) => SpaceDesignStub(call: call, name: 'meet');
}
