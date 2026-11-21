// genetic_disease_engine.dart —— 人类遗传病引擎（纯 Dart，跨平台）
//
// 课标 3.3.6：人类遗传病是可检测和预防的。
// ① 遗传病分类速览（数据常量）；② 遗传咨询计算：单基因遗传病
// 子代患病风险（常染色体显/隐 + X 连锁）。输入为基因型字符串。

/// 遗传病分类条目（速查用）。
class DiseaseType {
  final String name; // 类别：单基因显性/单基因隐性/伴X显性/伴X隐性/多基因/染色体异常
  final String inheritance; // 遗传特点一句话
  final List<String> examples; // 常见病举例
  const DiseaseType({
    required this.name,
    required this.inheritance,
    required this.examples,
  });
}

/// 常见单基因/X连锁遗传病速查（人教版必修2口径）。
const List<DiseaseType> diseaseCatalog = [
  DiseaseType(
    name: '常染色体显性',
    inheritance: '患者双亲常有一方患病；连续遗传；男女患病机会均等',
    examples: ['多指（趾）', '并指', '软骨发育不全'],
  ),
  DiseaseType(
    name: '常染色体隐性',
    inheritance: '双亲可都正常（携带者）；隔代遗传；近亲婚配风险高',
    examples: ['白化病', '先天性聋哑', '苯丙酮尿症', '镰刀型细胞贫血'],
  ),
  DiseaseType(
    name: '伴 X 显性',
    inheritance: '女性患者多于男性；患者常连续遗传；父病女必病',
    examples: ['抗维生素 D 佝偻病'],
  ),
  DiseaseType(
    name: '伴 X 隐性',
    inheritance: '男性患者多于女性；隔代交叉遗传；母病子必病，女病父必病',
    examples: ['红绿色盲', '血友病'],
  ),
  DiseaseType(
    name: '多基因遗传病',
    inheritance: '由多对等位基因控制；群体发病率较高，受环境影响',
    examples: ['原发性高血压', '青少年型糖尿病', '唇裂'],
  ),
  DiseaseType(
    name: '染色体异常遗传病',
    inheritance: '染色体结构或数目异常引起；多发流产、畸形',
    examples: ['21 三体综合征', '猫叫综合征（5 号缺失）', '性腺发育不全（XO）'],
  ),
];

/// 遗传咨询计算结果。
class DiseaseRiskResult {
  final List<String> fatherGametes;
  final List<String> motherGametes;
  final Map<String, double> offspring; // 基因型 → 概率
  final double affectedRate; // 患病率
  final double carrierRate; // 携带者率（隐性模式 = 杂合率；显性模式 = 0）
  final String note; // 计算说明
  const DiseaseRiskResult({
    required this.fatherGametes,
    required this.motherGametes,
    required this.offspring,
    required this.affectedRate,
    required this.carrierRate,
    required this.note,
  });
}

/// 单基因遗传病子代风险。
/// [father]/[mother]：如 'Aa'、'aa'、'XAY'、'XDXd'。
/// [mode]：'dom'（显性患病）或 'rec'（隐性患病）。
/// 支持：常染色体一对等位基因（同一字母大小写）；X 连锁（含 Y 为雄性，
/// 等位基因挂 X 上，如 'XAY'）。
DiseaseRiskResult mendelianRisk({
  required String father,
  required String mother,
  required String mode,
}) {
  if (mode != 'dom' && mode != 'rec') {
    throw ArgumentError('模式必须为 dom（显性患病）或 rec（隐性患病）');
  }
  final f = _parseGenotype(father, '父亲');
  final m = _parseGenotype(mother, '母亲');
  final sexLinked = f.containsY || m.containsY;
  // 配子拆分
  final fG = _gametes(f, '父亲');
  final mG = _gametes(m, '母亲');
  final offspring = <String, double>{};
  var affected = 0.0;
  var carrier = 0.0;
  for (final g1 in fG) {
    for (final g2 in mG) {
      final geno = sexLinked
          ? _combineSexLinked(g1, g2)
          : _combineAutosomal(g1, g2);
      final p = 1.0 / (fG.length * mG.length);
      offspring[geno] = (offspring[geno] ?? 0) + p;
      if (sexLinked) {
        // 伴 X：只统计有 X 的后代；患病判定按含显性等位基因（dom）
        // 或纯合隐性（rec）。简化：色盲模型 'Xa'（a=隐性疾病等位基因）。
        final xAlleles =
            geno.split('X').skip(1).map((s) => s.substring(0, 1)).toList()
              ..removeWhere((s) => s == 'Y');
        if (xAlleles.isNotEmpty) {
          if (mode == 'dom' && xAlleles.any((a) => a != 'a')) {
            affected += p;
          } else if (mode == 'rec' &&
              xAlleles.isNotEmpty &&
              xAlleles.every((a) => a == 'a')) {
            affected += p;
          } else if (mode == 'rec' &&
              xAlleles.length == 2 &&
              // 携带者 = **恰一条** X 带 a（XAXa）。旧判据 `any(!='a')` 把
              // XAXA 纯合显性也算成携带者——「携带者母亲 × 正常父亲」会印出
              // 携带者 50%（应为 25%）。备份仓 v2.19.163 同款病灶，
              // 照其诊断修正（纯合显性 = 完全正常，不是携带者）。
              xAlleles.where((a) => a == 'a').length == 1) {
            carrier += p;
          }
        }
      } else {
        final hasDominant =
            geno.split('').any((c) => c.toUpperCase() == c);
        final twoRecessive = _isRecessiveHom(geno);
        if (mode == 'dom' && hasDominant) {
          affected += p;
        } else if (mode == 'rec' && twoRecessive) {
          affected += p;
        } else if (mode == 'rec' &&
            !twoRecessive &&
            geno.length == 2 &&
            geno[0] != geno[1]) {
          carrier += p;
        }
      }
    }
  }
  return DiseaseRiskResult(
    fatherGametes: fG,
    motherGametes: mG,
    offspring: offspring,
    affectedRate: affected,
    carrierRate: carrier,
    note: sexLinked ? '伴 X 遗传（含雌雄后代）' : '常染色体单基因遗传',
  );
}

class _Parsed {
  final String raw;
  final bool containsY;
  _Parsed(this.raw, this.containsY);
}

_Parsed _parseGenotype(String raw, String who) {
  final s = raw.trim(); // 保留大小写（Aa 的显隐信息关键）
  if (s.isEmpty) throw ArgumentError('$who 基因型不能为空');
  final legal = RegExp(r'^[A-Za-z]+$');
  if (!legal.hasMatch(s)) {
    throw ArgumentError('$who 基因型只能包含字母（如 Aa / XAY）');
  }
  return _Parsed(s, s.contains('Y'));
}

List<String> _gametes(_Parsed p, String who) {
  final s = p.raw;
  if (p.containsY) {
    // 伴 X 雄：'XAY' → ['XA', 'Y']
    final xAllele = s.length >= 2 ? s.substring(1, 2) : 'A';
    return ['X$xAllele', 'Y'];
  }
  if (s.startsWith('X') && s.length == 4) {
    // 伴 X 雌：'XDXd' → ['XD', 'Xd']
    return [s.substring(0, 2), s.substring(2, 4)];
  }
  if (s.length == 2) {
    // 常染色体：'Aa' → ['A', 'a']
    return [s[0], s[1]];
  }
  throw ArgumentError('$who 基因型格式不支持（常染色体需两位点，如 Aa；X 连锁需 XAY / XDXd 形式）');
}

String _combineAutosomal(String g1, String g2) => '$g1$g2';

String _combineSexLinked(String g1, String g2) {
  final parts = [g1, g2]..sort();
  return '${parts[0]}${parts[1]}';
}

bool _isRecessiveHom(String geno) {
  if (geno.length != 2) return false;
  return geno[0] == geno[1] && geno[0].toUpperCase() != geno[0];
}