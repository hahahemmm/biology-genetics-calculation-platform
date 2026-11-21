# Biology · Genetics Calculation Platform

**English** | [简体中文](README.zh-CN.md)

See every step of a genetics problem — find where it went wrong at a glance.

An educational tool for high-school biology. Rather than only showing the final answer, it lays out
gametes, Punnett squares, probabilities and pedigrees; the same problem is solved twice — by
decomposition and by gamete pooling — so students can see the exact step where their reasoning
diverged.

Current version: **0.1.0** (first public release).

## Features

| Module | What it does |
|---|---|
| Pedigree builder | Multi-locus, multi-generation pedigree tree with per-generation genotype and phenotype probabilities; explicit mating links, sex-linked traits, linkage with recombination, lethal genotypes and polyploidy |
| Two-locus 9:3:3:1 | The 9:3:3:1 ratio and all common variants (9:7, 9:3:4, 15:1, 1:4:6:4:1, …) |
| Three-locus | Punnett square and ratio derivation for three independently assorting loci |
| Single-locus cross | Segregation, test cross, back cross, incomplete dominance, codominance, lethals |
| Sex-linked | X-linked inheritance with conditional probabilities by sex |
| Method comparison | Decomposition vs gamete pooling side by side, to locate the first wrong step |
| Linkage and crossing-over | AB/ab notation with recombination frequency; parental and recombinant gametes |
| Random mating | Gamete-pool and enumeration solutions, generation by generation |
| Genetic engineering | Restriction digests (EcoRI / BamHI / HindIII), virtual PCR and gel electrophoresis |
| Population growth | Exponential (J-shaped) growth against continuous logistic growth |
| Knowledge graph | 19-node prerequisite/relation graph with a quick-reference index |
| Mistake notebook | Entry, error-cause tagging, review status tracking |
| Local profiles | Multiple users on one machine, each with its own notebook and settings, optional 4-digit launch PIN |
| Data bundle | Whole-machine data exported to one passphrase-encrypted file, restorable in place |
| Ask AI | Side panel that carries the current page and calculation context; optional web search, page fetch, local Python and shell (confirmed per run) |
| Onboarding | A guided tour on first launch; skippable, replayable from settings |

## Versioning and compatibility

**Backward compatibility is not guaranteed.**

Before 1.0, any release may contain breaking, irreversible or otherwise incompatible changes,
including but not limited to:

- the on-disk data format and directory layout;
- configuration keys, defaults and locations;
- the format of backup/export bundles (an old bundle may not import into a newer build);
- UI flows and keyboard shortcuts.

Export a backup before upgrading and do not assume old data will be readable. This is deliberate:
the feature set is still moving quickly, and maintaining a migration layer for every past format
would slow down each change and leave the code full of branches that only serve history.

## Supported platforms

| Platform | Status |
|---|---|
| Windows | Primary target; build commands below |
| Web | Builds and runs |
| Android | Builds |
| macOS | Scaffolding in place; sandbox adaptation not done |

## Getting started

Flutter **3.47.1** or a compatible version (Dart SDK ^3.13.1).

```bash
git clone https://github.com/hahahemmm/biology-genetics-calculation-platform.git
cd biology-genetics-calculation-platform
flutter pub get
flutter run -d windows     # or -d chrome / -d macos
```

## Building

```bash
flutter build windows --release
flutter build web --release
flutter build apk --release
```

## Configuring the AI features

**This repository contains no API key.** `dart_defines.example.json` is a template with empty
fields.

There are two ways to configure a provider:

1. In the app under Settings → AI, enter Base URL / key / model. The key is stored locally,
   encrypted with a machine-bound passphrase.
2. At build time: `--dart-define-from-file=dart_defines.local.json` (already in `.gitignore` —
   never commit it).

Any OpenAI-compatible `/chat/completions` endpoint works. Without a key, every calculation
feature still works; only “Ask AI” is unavailable.

Local Python and shell execution under “AI tools” are off by default and always ask for
confirmation before running.

## Project layout

```
lib/
  engine/     Pure Dart domain engines, no Flutter dependency
  services/   HTTP clients, encrypted storage, backup, AI tooling
  state/      Global state and persistence
  pages/      Pages and calculator widgets
  ui/         Shared UI components and platform adapters
  charts/     Chart painting
  data/       Built-in data (curriculum, card decks, presets, knowledge entries)
  guide/      Onboarding
  models/     Knowledge data models
  storage/    Platform storage abstraction
data/         Curriculum and exam-point JSON (with source notes)
docs/         Architecture notes
test/         Unit / widget / golden tests
```

Architecture details and design conventions in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Layering rule: `lib → engine`, and the engine never depends upwards nor imports Flutter. This is
enforced by `test/layer_purity_test.dart`.

## Testing

```bash
flutter analyze
flutter test
flutter test --update-goldens    # only when the visual change is intended
```

## Data and sources

Curriculum and exam-point entries under `data/` carry source notes and follow the Chinese
Ministry of Education *Biology Curriculum Standard for Senior High School (2017 edition, revised
2020)*. Biological database entries come from public metadata in UniProt / RCSB PDB / PubMed.

This repository contains no textbook text; curriculum statements follow the standard document
itself. Restriction digests, PCR and population growth are **teaching simplifications** meant to
illustrate principles, not for real experimental design or quantitative prediction.

## About the development process

This project was built with AI assistance: implementation, refactoring, testing, review and
documentation all involved AI. All feature decisions, content choices and final acceptance are the
author's.

## Contributing

Issues and pull requests are welcome — please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

- Change history: [CHANGELOG.md](CHANGELOG.md)
- Reporting security issues: [SECURITY.md](SECURITY.md) (please do not open a public issue)

## Continuous integration

`.github/workflows/ci.yml` runs `flutter analyze` and `flutter test` on every push and pull
request. Run both locally before opening a PR.

## License

[MIT](LICENSE). Third-party dependencies and fonts are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
