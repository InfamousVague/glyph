import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

/// Stage one's screen: the kit, on the phone. Replaced by the app's own home once the shell is ported.
class KitGallery extends StatelessWidget {
  const KitGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(child: Text('Ghost Flutter', style: t.text('2xl', weight: 'bold')));
  }
}
