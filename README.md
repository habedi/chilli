<div align="center">
  <picture>
    <img alt="Chilli Logo" src="logo.svg" height="25%" width="25%">
  </picture>
<br>

<h2>Chilli</h2>

[![Tests](https://img.shields.io/github/actions/workflow/status/habedi/chilli/tests.yml?label=tests&style=flat&labelColor=282c34&logo=github)](https://github.com/habedi/chilli/actions/workflows/tests.yml)
[![Code Coverage](https://img.shields.io/codecov/c/github/habedi/chilli?label=coverage&style=flat&labelColor=282c34&logo=codecov)](https://codecov.io/gh/habedi/chilli)
[![CodeFactor](https://img.shields.io/codefactor/grade/github/habedi/chilli?label=code%20quality&style=flat&labelColor=282c34&logo=codefactor)](https://www.codefactor.io/repository/github/habedi/chilli)
[![License](https://img.shields.io/badge/license-MIT-007ec6?label=license&style=flat&labelColor=282c34&logo=open-source-initiative)](https://github.com/habedi/chilli/blob/main/LICENSE)
[![Zig Version](https://img.shields.io/badge/Zig-0.14.1-orange?logo=zig&labelColor=282c34)](https://ziglang.org/download/)
[![Release](https://img.shields.io/github/release/habedi/chilli.svg?label=release&style=flat&labelColor=282c34&logo=github)](https://github.com/habedi/chilli/releases/latest)

A microframework for creating command line applications in Zig

</div>

---

Chilli is a lightweight command line interface (CLI) framework for Zig programming language.
Its goal is to make it easy to create structured, maintainable, and user-friendly CLIs with minimal boilerplate,
while being small and fast, and not get in the way of your application logic.

> [!IMPORTANT]
> Chilli is in the early stages of development and is not yet ready for serious use.
> The API is not stable and may change without notice.

### Feature Checklist

-   [x] **Command Structure**
    -   [x] Nested commands and subcommands
    -   [x] Command aliases
    -   [x] Persistent flags (flags on parent commands are available to children)

-   [x] **Argument & Flag Parsing**
    -   [x] Long flags (`--verbose`), short flags (`-v`), and grouped boolean flags (`-vf`)
    -   [x] Type-safe flag access (like `ctx.getFlag("count", i64)`)
    - [~] Positional Arguments (supports required & optional; no variadic support yet)

-   [x] **Help & Usage Output**
    -   [x] Automatic and context-aware help generation (`--help`)
    -   [x] Clean, aligned help output for commands, flags, and arguments
    -   [x] Version display (automatic `--version` flag)

-   [x] **Developer Experience**
    -   [x] Context data for passing application state
    -   [x] Reading options from environment variables
    -   [ ] Named access for positional arguments (access is currently by index)
    -   [ ] Deprecation notices for commands or flags
    -   [ ] Built-in TUI components (like spinners and progress bars)

---

### Getting Started

You can add Chilli to your project with a single command.
The Zig build system will download it, verify its contents, and add it to your `build.zig.zon` manifest automatically.

#### 1. Fetch the Dependency

Run the following command in the root directory of your project:

```sh
zig fetch --save=chilli "https://github.com/habedi/chilli/archive/main.tar.gz"
```

This command fetches the latest version from the `main` branch and adds it to your `build.zig.zon` under the name
`chilli`.

#### 2. Use the Dependency in `build.zig`

Next, modify your `build.zig` file to get the dependency from the builder and make it available to your executable as a
module.

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "your-cli-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 1. Get the dependency object from the builder
    const chilli_dep = b.dependency("chilli", .{});

    // 2. Get chilli's top-level module
    const chilli_module = chilli_dep.module("chilli");

    // 3. Add the module to your executable so you can @import("chilli")
    exe.root_module.addImport("chilli", chilli_module);

    b.installArtifact(exe);
}
```

#### 3. Write Your Application Code

Finally, you can `@import("chilli")` and start building your application in `src/main.zig`.

```zig
const std = @import("std");
const chilli = @import("chilli");

// A function for our command to execute
fn greet(ctx: chilli.CommandContext) !void {
    const name = ctx.getFlag("name", []const u8);
    const excitement = ctx.getFlag("excitement", u32);

    std.print("Hello, {s}", .{name});
    var i: u32 = 0;
    while (i < excitement) : (i += 1) {
        std.print("!", .{});
    }
    std.print("\n", .{});
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create the root command for your application
    var root_cmd = try chilli.Command.init(allocator, .{
        .name = "your-cli-app",
        .description = "A new CLI built with Chilli",
        .version = "v0.1.0",
        .exec = greet, // The function to run
    });
    defer root_cmd.deinit();

    // Add flags to the command
    try root_cmd.addFlag(.{
        .name = "name",
        .shortcut = "n",
        .description = "The name to greet",
        .type = .String,
        .default_value = .{ .String = "World" },
    });
    try root_cmd.addFlag(.{
        .name = "excitement",
        .type = .Int,
        .description = "How excited to be",
        .default_value = .{ .Int = 1 },
    });

    // Hand control over to the framework
    try root_cmd.run(null);
}
```

### Examples

| File                                      | Description                                                        |
|-------------------------------------------|--------------------------------------------------------------------|
| [simple_cli.zig](examples/simple_cli.zig) | A simple CLI application that shows basic command and flag parsing |

-----

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to make a contribution.

### License

Chilli is licensed under the MIT License ([LICENSE](LICENSE)).

### Acknowledgements

* The logo is from [SVG Repo](https://www.svgrepo.com/svg/45673/chili-pepper).
