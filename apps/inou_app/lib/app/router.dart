import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/analytics/presentation/analytics_page.dart';
import '../features/home/presentation/home_page.dart';
import '../features/library/presentation/library_page.dart';
import '../features/photo_search/presentation/photo_search_page.dart';
import '../features/practice/presentation/practice_page.dart';
import '../features/review/presentation/split_proofread_page.dart';
import '../features/wrongbook/presentation/wrongbook_page.dart';
import 'adaptive_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AdaptiveShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomePage(),
              ),
              GoRoute(
                path: '/photo-search',
                builder: (context, state) => const PhotoSearchPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/practice',
                builder: (context, state) => const PracticePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/wrongbook',
                builder: (context, state) => const WrongbookPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/analytics',
                builder: (context, state) => const AnalyticsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/review',
        builder: (context, state) => const SplitProofreadPage(),
      ),
    ],
  );
});
