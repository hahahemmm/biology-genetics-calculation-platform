// engine.dart —— 聚合导出（纯 Dart）
//
//
// 汇总各引擎的公开 API，供 UI 层（future lib/）一键 import 'package:.../engine.dart'。
// 本文件只 re-export，不包含业务逻辑。

export 'models.dart';
export 'fraction.dart';
export 'genetics_env.dart';
export 'cross_engine.dart';
export 'kaoji_calc.dart';
export 'pedigree.dart';
export 'pedigree_engine.dart';
export 'sex_linked_engine.dart';
export 'linkage_engine.dart';
export 'method_compare.dart';
export 'random_mating_engine.dart';
export 'knowledge_graph.dart';
export 'dna_engine.dart';
export 'dna_strand_engine.dart';
export 'ploidy_engine.dart';
// v2.11 M2：补全 9 个漏导（之前 0 调用方，barrel 实质是死代码）
export 'error_diagnosis.dart';
export 'mutation_engine.dart';
export 'genetic_disease_engine.dart';
export 'reverse_engine.dart';
export 'kaodian_loader.dart';
export 'syllabus_loader.dart';
export 'pedigree_graph.dart';
export 'gene_frequency.dart';
