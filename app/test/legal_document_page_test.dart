import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/privacy.dart';
import 'package:nnbdc/page/protocol.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/widget/app_scaffold.dart';
import 'package:nnbdc/widget/frosted_glass_card.dart';
import 'package:nnbdc/widget/legal_document_page.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestApp(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DarkMode>(create: (_) => DarkMode()),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  testWidgets('ProtocolPage 和 PrivacyPage 均能正常构建，包含 AppScaffold 和 FrostedGlassCard', (tester) async {
    // 渲染 ProtocolPage
    await tester.pumpWidget(buildTestApp(const ProtocolPage()));
    expect(find.byType(LegalDocumentPage), findsOneWidget);
    expect(find.byType(AppScaffold), findsOneWidget);
    expect(find.byType(FrostedGlassCard), findsOneWidget);
    expect(find.text('用户使用协议'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

    // 渲染 PrivacyPage
    await tester.pumpWidget(buildTestApp(const PrivacyPage()));
    expect(find.byType(LegalDocumentPage), findsOneWidget);
    expect(find.byType(AppScaffold), findsOneWidget);
    expect(find.byType(FrostedGlassCard), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
  });
}
