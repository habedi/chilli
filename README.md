## Zig Project Template

<div align="center">
  <picture>
    <img alt="Zig Logo" src="docs/assets/logo/zero.svg" height="35%" width="35%">
  </picture>
</div>
<br>

[![Tests](https://img.shields.io/github/actions/workflow/status/habedi/template-zig-project/tests.yml?label=tests&style=flat&labelColor=282c34&logo=github)](https://github.com/habedi/template-zig-project/actions/workflows/tests.yml)
[![Lints](https://img.shields.io/github/actions/workflow/status/habedi/template-zig-project/lints.yml?label=lints&style=flat&labelColor=282c34&logo=github)](https://github.com/habedi/template-zig-project/actions/workflows/lints.yml)
[![Code Coverage](https://img.shields.io/codecov/c/github/habedi/template-zig-project?label=coverage&style=flat&labelColor=282c34&logo=codecov)](https://codecov.io/gh/habedi/template-zig-project)
[![CodeFactor](https://img.shields.io/codefactor/grade/github/habedi/template-zig-project?label=code%20quality&style=flat&labelColor=282c34&logo=codefactor)](https://www.codefactor.io/repository/github/habedi/template-zig-project)
[![Docs](https://img.shields.io/badge/docs-latest-007ec6?label=docs&style=flat&labelColor=282c34&logo=readthedocs)](docs)
[![License](https://img.shields.io/badge/license-MIT-007ec6?label=license&style=flat&labelColor=282c34&logo=open-source-initiative)](https://github.com/habedi/template-zig-project/blob/main/LICENSE)
[![Release](https://img.shields.io/github/release/habedi/template-zig-project.svg?label=release&style=flat&labelColor=282c34&logo=github)](https://github.com/habedi/template-zig-project/releases/latest)

This is a project template for Zig projects.
It provides a minimalistic project structure with pre-configured GitHub Actions, Makefile, and a few useful
configuration files.
I share it here in case it might be useful to others.

### Features

- Minimalistic project structure
- Pre-configured GitHub Actions for linting and testing
- Makefile for managing the development workflow and tasks like code formatting, testing, linting, etc.
- GitHub badges for tests, code quality and coverage, documentation, etc.
- [Code of Conduct](CODE_OF_CONDUCT.md) and [Contributing Guidelines](CONTRIBUTING.md)

### Getting Started

Check out the [Makefile](Makefile) for available commands to manage the development workflow of the project.

```shell
# Install system and development dependencies (for Debian-based systems)
sudo apt-get install make
make install-deps
```

```shell
# See all available commands and their descriptions
make help
```

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to make a contribution.

### License

This project is licensed under the MIT License ([LICENSE](LICENSE) or https://opensource.org/licenses/MIT)
