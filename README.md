## Chilli

<div align="center">
  <picture>
    <img alt="Chilli Logo" src="logo.svg" height="25%" width="25%">
  </picture>
</div>
<br>

[![Tests](https://img.shields.io/github/actions/workflow/status/habedi/chilli/tests.yml?label=tests&style=flat&labelColor=282c34&logo=github)](https://github.com/habedi/chilli/actions/workflows/tests.yml)
[![Code Coverage](https://img.shields.io/codecov/c/github/habedi/chilli?label=coverage&style=flat&labelColor=282c34&logo=codecov)](https://codecov.io/gh/habedi/chilli)
[![CodeFactor](https://img.shields.io/codefactor/grade/github/habedi/chilli?label=code%20quality&style=flat&labelColor=282c34&logo=codefactor)](https://www.codefactor.io/repository/github/habedi/chilli)
[![License](https://img.shields.io/badge/license-MIT-007ec6?label=license&style=flat&labelColor=282c34&logo=open-source-initiative)](https://github.com/habedi/chilli/blob/main/LICENSE)
[![Zig Version](https://img.shields.io/badge/Zig-0.14.1-orange?logo=zig&labelColor=282c34)](https://ziglang.org/download/)
[![Release](https://img.shields.io/github/release/habedi/chilli.svg?label=release&style=flat&labelColor=282c34&logo=github)](https://github.com/habedi/chilli/releases/latest)

---

Chilli is a command line interface (CLI) framework for Zig that provides tools for building and managing command line
applications in Zig.

> [!IMPORTANT]
> This library is in very early stages of development and is not yet ready for serious use.
> The API is not stable and may change frequently.
> Additionally, it's not thoroughly tested or optimized so use it at your own risk.

### Features

* **Modular and Clean Architecture**: The library is built with a clear separation of concerns, dividing core logic into
  separate modules for commands, parsing, context, and utilities.
* **Intuitive Command Structure**: Easily build nested command-and-subcommand hierarchies, inspired by popular
  frameworks like Cobra and `git`.
* **Type-Safe Flag Access**: Retrieve flag values with compile-time type validation. The API prevents type-mismatches
  and helps catch bugs early.
* **Flexible Argument Handling**: Supports a variety of command-line arguments:
    * Flags with long names (`--flag-name`).
    * Short flags (`-f`) with support for basic grouping.
    * Positional arguments, which can be marked as `required` or `optional`.
* **Automatic Help Generation**: `chilli` automatically generates formatted help messages for commands, including usage,
  flags, arguments, and grouped subcommands.
* **Integrated Default Values**: Easily set default values for flags of any supported type (`bool`, `int`, `string`) to
  simplify user code and configuration.
* **Contextual State Management**: Pass a single, user-defined data struct (e.g., application configuration or state) to
  the root command, making it accessible from any subcommand's execution function.
* **Fast and Efficient Parsing**: The argument parsing engine uses a single pass over command-line arguments for minimal
  overhead.
* **Rich Output Support**: Includes a built-in module for ANSI escape codes, enabling you to add color and styling to
  your CLI output.

---

### Getting Started

To be added.

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to make a contribution.

### Logo

The logo is from [SVG Repo](https://www.svgrepo.com/svg/45673/chili-pepper).

### License

Chilli is licensed under the MIT License ([LICENSE](LICENSE)).
