import 'package:go_router/go_router.dart';
import 'package:nnbdc/page/admin.dart';
import 'package:nnbdc/page/ai_activation.dart';
import 'package:nnbdc/page/ai_diagnostic.dart';
import 'package:nnbdc/page/bdc/bdc.dart';
import 'package:nnbdc/page/walkman.dart';
import 'package:nnbdc/page/farm.dart';
import 'package:nnbdc/page/finish.dart';
import 'package:nnbdc/page/first.dart';
import 'package:nnbdc/page/game.dart';
import 'package:nnbdc/page/index.dart';
import 'package:nnbdc/page/login.dart';
import 'package:nnbdc/page/email_login.dart';
import 'package:nnbdc/page/msg.dart';
import 'package:nnbdc/page/pic_search.dart';
import 'package:nnbdc/page/privacy.dart';
import 'package:nnbdc/page/protocol.dart';
import 'package:nnbdc/page/russia.dart';
import 'package:nnbdc/page/search.dart';
import 'package:nnbdc/page/select_book.dart';
import 'package:nnbdc/page/word_detail.dart';
import 'package:nnbdc/page/word_lists.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/page/admin/admin_image_review_page.dart';
import 'package:nnbdc/page/word_list/import_from_book_page.dart';
import 'package:nnbdc/page/word_list/import_from_scan_page.dart';
import 'package:nnbdc/page/admin/golden_master_tool.dart';
import 'package:nnbdc/page/study_stats.dart';
import 'package:nnbdc/test.dart';
import 'services/dialog_service.dart';

final goRouter = GoRouter(
  navigatorKey: DialogService.navigatorKey,
  initialLocation: '/first',
  routes: [
    GoRoute(path: '/test', builder: (context, state) => TestPage()),
    GoRoute(path: '/first', builder: (context, state) => const FirstPage()),
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
    GoRoute(path: '/email_login', builder: (context, state) => const EmailLoginPage()),
    GoRoute(path: '/index', builder: (context, state) => const IndexPage()),
    GoRoute(path: '/protocol', builder: (context, state) => const ProtocolPage()),
    GoRoute(path: '/privacy', builder: (context, state) => const PrivacyPage()),
    GoRoute(path: '/pic_search', builder: (context, state) => const PicSearchPage()),
    GoRoute(
      path: '/select_book',
      builder: (context, state) => const SelectBookPage(),
    ),
    GoRoute(
      path: '/bdc',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: BdcPage(),
      ),
    ),
    GoRoute(path: '/walkman', builder: (context, state) => const WalkmanPage()),
    GoRoute(path: '/game', builder: (context, state) => const GamePage()),
    GoRoute(path: '/russia', builder: (context, state) => const RussiaPage()),
    GoRoute(path: '/word_detail', builder: (context, state) => const WordDetailPage()),
    GoRoute(path: '/word_list', builder: (context, state) => const WordListPage()),
    GoRoute(path: '/import_from_book', builder: (context, state) => ImportFromBookPage(wordModifier: state.extra as WordModifier)),
    GoRoute(path: '/import_from_scan', builder: (context, state) => ImportFromScanPage(wordModifier: state.extra as WordModifier)),
    GoRoute(path: '/finish', builder: (context, state) => const FinishPage()),
    GoRoute(path: '/farm', builder: (context, state) => const FarmPage()),
    GoRoute(path: '/word_lists', builder: (context, state) => const WordListsPage()),
    GoRoute(path: '/msg', builder: (context, state) => const MsgPage()),
    GoRoute(path: '/search', builder: (context, state) => const SearchPage()),
    GoRoute(path: '/admin', builder: (context, state) => const AdminPage()),
    GoRoute(path: '/admin_image_review', builder: (context, state) => const AdminImageReviewPage()),
    GoRoute(path: '/ai_activation', builder: (context, state) => const AiActivationPage()),
    GoRoute(path: '/ai_diagnostic', builder: (context, state) => const AiDiagnosticPage()),
    GoRoute(path: '/golden_master', builder: (context, state) => const GoldenMasterToolPage()),
    GoRoute(path: '/study_stats', builder: (context, state) => const StudyStatsPage()),
  ],
);
