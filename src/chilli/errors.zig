//! This module defines all public errors that can be returned by the Chilli framework.
//!
//! Consolidating errors here provides a single source of truth for error handling
//! and makes it easier for users of the library to catch specific failures.
const std = @import("std");

/// A comprehensive set of all possible errors returned by the Chilli framework.
pub const Error = error{
/// An unknown flag was provided (e.g., `--nonexistent`).
    UnknownFlag,
/// A flag that requires a value was provided without one (e.g., `--output` at the end of the line).
    MissingFlagValue,
/// Short flags were grouped incorrectly (e.g., a non-boolean flag was not the last in a group).
    InvalidFlagGrouping,
/// A command was invoked without one of its required positional arguments.
    MissingRequiredArgument,
/// A command was invoked with more positional arguments than it accepts.
    TooManyArguments,
/// An invalid string was provided for a boolean flag (must be "true" or "false").
    InvalidBoolString,
} || std.fmt.ParseIntError || std.mem.Allocator.Error; // Includes parsing and memory allocation errors.
