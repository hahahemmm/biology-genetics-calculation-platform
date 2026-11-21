// pedigree.dart —— 系谱分析（基础，纯 Dart）
//
//
// 实现常染色体显/隐、伴 X 显/隐的后代患病概率推断。
//
// 生物学语义模型：
//   - 常染色体显性遗传（AD）：AA、Aa 患病；aa 正常。任一亲本患病即可能传病。
//   - 常染色体隐性遗传（AR）：aa 患病；AA、Aa 正常（Aa 为携带者）。双方均须带 a 才可能出患病后代。
//   - 伴 X 显性遗传（XD）：X 上显性基因，只要含该显性基因即患病；女性 XX（XAXa 病）、男性 XY（XAY 病）。
//   - 伴 X 隐性遗传（XR）：女性需 XaXa 患病，男性只要 XaY 即患病（半合子）。
//
// 本文件提供「给定双亲基因型 → 后代患病概率」的基础函数，以及常见遗传方式的
// 已知判定常量。更深入的系谱图构建由 UI 层负责。

/// 遗传方式。
enum InheritanceMode {
  autosomalDominant, // 常染色体显性
  autosomalRecessive, // 常染色体隐性
  xLinkedDominant, // 伴 X 显性
  xLinkedRecessive, // 伴 X 隐性
}

/// 系谱分析引擎（基础）。
class Pedigree {
  /// 常染色体：给定双亲基因型（如 'Aa'、'aa'），返回后代各基因型的概率（比例）。
  ///
  /// 返回 Map<基因型, 比例整数>，用 4 为分母（单基因杂交 × 4）。
  Map<String, int> offspringGenotypes(String p1, String p2) {
    final g1 = p1.split('');
    final g2 = p2.split('');
    final cnt = <String, int>{};
    for (final a in g1) {
      for (final b in g2) {
        final key = _norm(a, b);
        cnt[key] = (cnt[key] ?? 0) + 1;
      }
    }
    return cnt;
  }

  /// 常染色体隐性遗传（AR）：患病 = aa。
  /// 返回后代患病概率（0..1 之间的小数，基于 1/4、1/2、0 等）。
  double autosomalRecessiveRisk(String p1, String p2) {
    final cnt = offspringGenotypes(p1, p2);
    int total = 0, affected = 0;
    cnt.forEach((gen, c) {
      total += c;
      if (gen == 'aa') affected += c;
    });
    if (total == 0) return 0;
    return affected / total;
  }

  /// 常染色体显性遗传（AD）：患病 = AA 或 Aa。
  /// 返回后代患病概率。
  double autosomalDominantRisk(String p1, String p2) {
    final cnt = offspringGenotypes(p1, p2);
    int total = 0, affected = 0;
    cnt.forEach((gen, c) {
      total += c;
      if (gen.contains('A')) affected += c; // AA / Aa 均患病
    });
    if (total == 0) return 0;
    return affected / total;
  }

  /// 伴 X 隐性遗传（XR）：给定双亲基因型（'XAXa' / 'XAY' 形式），返回后代患病概率。
  ///
  /// 约定输入含 X 与等位基因字母（如 XAXa、XaY）。父亲的 Y 不携带等位基因。
  double xLinkedRecessiveRisk(String motherGenotype, String fatherGenotype) {
    // 母亲提供两个 X 配子，父亲提供 X 或 Y。
    // 【关键】直接用原始字符判断大小写，不能 toUpperCase 后把 a 误判成 A。
    final motherX = <String>[]; // 母亲 X 上的等位基因（原样保留 A / a）
    for (final ch in motherGenotype.split('')) {
      if (ch == 'X') continue;
      if (ch == 'A' || ch == 'a') motherX.add(ch);
    }
    // 父亲 X 上的等位基因（若为 XAY / XaY）
    String? fatherX;
    for (final ch in fatherGenotype.split('')) {
      if (ch == 'X') continue;
      if (ch == 'Y') continue;
      if (ch == 'A' || ch == 'a') fatherX = ch;
    }

    // 后代：
    //  女儿：motherX × fatherX，患病需 XaXa
    //  儿子：motherX × Y，患病需 XaY（半合子）
    int totalSons = 0, affectedSons = 0;
    int totalDaughters = 0, affectedDaughters = 0;
    for (final m in motherX) {
      totalSons++;
      if (m == 'a') affectedSons++; // 儿子 XaY 患病
      if (fatherX != null) {
        totalDaughters++;
        if (m == 'a' && fatherX == 'a') affectedDaughters++; // 女儿 XaXa 患病
      }
    }
    final sonsRisk = totalSons == 0 ? 0.0 : affectedSons / totalSons;
    final daughtersRisk = totalDaughters == 0 ? 0.0 : affectedDaughters / totalDaughters;
    return sonsRisk; // 通常题目问儿子患病概率；也可取 daughterRisk
  }

  /// 伴 X 显性遗传（XD）：女性 XAXa / XAXA 患病，male XAY 患病。
  /// 返回儿子/女儿的患病概率（注意伴 X 显性无携带者：只要含 A 即患病）。
  (double sons, double daughters) xLinkedDominantRisk(
      String motherGenotype, String fatherGenotype) {
    final motherX = <String>[];
    for (final ch in motherGenotype.split('')) {
      if (ch == 'X') continue;
      if (ch == 'A' || ch == 'a') motherX.add(ch);
    }
    String? fatherX;
    for (final ch in fatherGenotype.split('')) {
      if (ch == 'X') continue;
      if (ch == 'Y') continue;
      if (ch == 'A' || ch == 'a') fatherX = ch;
    }
    int totalSons = 0, affectedSons = 0;
    int totalDaughters = 0, affectedDaughters = 0;
    for (final m in motherX) {
      totalSons++;
      if (m == 'A') affectedSons++; // 儿子 XAY 患病
      if (fatherX != null) {
        totalDaughters++;
        if (m == 'A' || fatherX == 'A') affectedDaughters++; // 女儿含 A 即患病
      }
    }
    final sonsRisk = totalSons == 0 ? 0.0 : affectedSons / totalSons;
    final daughtersRisk =
        totalDaughters == 0 ? 0.0 : affectedDaughters / totalDaughters;
    return (sonsRisk, daughtersRisk);
  }

  String _norm(String a, String b) {
    if (a == b) return a + b; // AA 或 aa
    final au = a.toUpperCase(), bu = b.toUpperCase();
    if (au != bu) {
      final aUp = a == au;
      final bUp = b == bu;
      if (aUp && !bUp) return au + bu.toLowerCase();
      if (bUp && !aUp) return bu + au.toLowerCase();
      return au.compareTo(bu) < 0 ? '$au$bu' : '$bu$au';
    }
    return au + au.toLowerCase(); // Aa / aA
  }
}
