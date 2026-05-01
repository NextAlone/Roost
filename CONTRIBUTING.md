# Contributing to Roost

Thank you for your interest in contributing to Roost. This guide covers the current Roost fork, which intentionally keeps several source directories named `Muxy/`, `MuxyShared/`, and `MuxyServer/` to reduce upstream merge conflicts.

## Humans Only Policy

Roost is a community project and we want communication to stay between humans. **AI-generated text is not allowed** in:

- Issue descriptions and comments
- Pull request titles, descriptions, summaries, and comments
- Discussion replies and code review comments

You are welcome to use AI to help you write code, but the text you post on GitHub must be written by you, in your own words. Issues and PRs with AI-generated text will be closed without review.

## Getting Started

### Prerequisites

- macOS 14+
- Swift 6.0+
- [SwiftLint](https://github.com/realm/SwiftLint) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) (`brew install swiftlint swiftformat`)

### Setup

Clone the Roost repository URL used by the project maintainers, then run:

```bash
scripts/setup.sh
swift build
swift run Roost
```

## Development Workflow

Roost development uses jj locally. GitHub may still be used as the hosting and review layer, but local history work should follow the repository's jj workflow.

1. Start from the current main change.
2. Make a focused change.
3. Run checks before describing or submitting the change:

```bash
scripts/checks.sh --fix
```

4. Describe or submit the change using the repository's current jj/GitHub workflow.

## Code Standards

- **No comments in the codebase** — all code must be self-explanatory and cleanly structured.
- **Early returns** over nested conditionals.
- **Fix root causes**, not symptoms.
- **Follow existing patterns** but suggest refactors if they improve quality.
- **Security first** — no command injection, XSS, secret leakage, or hidden privilege escalation.

## Checks

All changes must pass the full check suite. Run it with a single command:

```bash
scripts/checks.sh
scripts/checks.sh --fix
```

The script runs formatting, linting, build, and tests, stopping on the first failure. Tool versions are pinned in `.tool-versions` and the script validates them on startup.

## Pull Request Guidelines

- Keep changes focused.
- Write a clear human-authored title and description explaining why the change exists.
- Ensure all checks pass before requesting review.
- Link related issues when applicable.

## Reporting Issues

- Use the [Bug Report](.github/ISSUE_TEMPLATE/bug_report.yml) template for bugs.
- Use the [Feature Request](.github/ISSUE_TEMPLATE/feature_request.yml) template for ideas.
- Search existing issues before creating a new one.

## License

By contributing, you agree that your contributions will be licensed under the project's current license terms.
