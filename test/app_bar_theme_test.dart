import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/main.dart';

void main() {
  testWidgets('the app bar keeps its color when a list scrolls under it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThrowLabApp.theme,
      home: Scaffold(
        appBar: AppBar(title: const Text('ThrowLab')),
        body: ListView(
          children: [
            for (var i = 0; i < 60; i++) ListTile(title: Text('Row $i')),
          ],
        ),
      ),
    ));
    Color barColor() => tester
        .widget<Material>(find
            .descendant(of: find.byType(AppBar), matching: find.byType(Material))
            .first)
        .color!;
    final resting = barColor();

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(barColor(), resting);
  });
}
