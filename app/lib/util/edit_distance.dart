/// 通用 Levenshtein 编辑距离
/// - 支持字符串（按字符）
/// - 支持任意 `List<T>`（按等值比较）
class EditDistance {
  /// 字符串的编辑距离
  static int forStrings(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final aList = a.split('');
    final bList = b.split('');
    return forLists(aList, bList);
  }

  /// 列表的编辑距离（元素用 == 比较，适用于 `List<T>`）
  static int forLists<T>(List<T> a, List<T> b) {
    final n = a.length;
    final m = b.length;
    if (n == 0) return m;
    if (m == 0) return n;

    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 0; i <= n; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= m; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final del = dp[i - 1][j] + 1;
        final ins = dp[i][j - 1] + 1;
        final sub = dp[i - 1][j - 1] + cost;
        dp[i][j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
    }
    return dp[n][m];
  }
}


