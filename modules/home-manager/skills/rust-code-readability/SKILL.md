---
name: rust-code-readability
description: >
  Improve the visual readability of Rust code through semantic
  whitespace grouping, clear function separation, and logical
  organization. Use when writing, modifying, reviewing, or
  finalizing Rust code, especially before declaring completion.
---

# Rust Code Readability

Write Rust code for humans who must read, understand, debug,
and audit it later.

Treat visual structure as part of code quality, not decoration.

## 1. Function Separation

Always separate adjacent function and method definitions with
exactly one blank line.

Bad:

```rust
fn foo() {
  do_something();
}
fn bar() {
  do_something_else();
}
```

Good:

```rust
fn foo() {
  do_something();
}

fn bar() {
  do_something_else();
}
```

Apply this consistently to free functions, impl methods,
test functions, and other adjacent items.

## 2. Semantic Whitespace Grouping

Within functions, use blank lines to separate logically
distinct phases of an operation.

Statements belonging to the same logical operation should
form a visual paragraph.

Common boundaries include:

- Setup -> execution
- Initialization -> mutation
- Input validation -> processing
- Data acquisition -> transformation
- State modification -> verification
- Independent operations
- Preparation -> side effects
- Processing -> return value construction

  Do not mechanically add a blank line after each statement.

  Bad:

  ```rust
  fn process() {
	  let config = load_config()?;
	  let input = read_input()?;
	  let parsed = parse(input)?;
	  let result = transform(parsed, &config);
	  save_result(&result)?;
	  Ok(result)
  }
  ```

  Good:

  ```rust
  fn process() {
	  let config = load_config()?;
	  let input = read_input()?;

	  let parsed = parse(input)?;
	  let result = transform(parsed, &config);

	  save_result(&result)?;

	  Ok(result)
  }
  ```

  ## 3. Test Readability

  Structure tests around recognizable phases:

  1. Setup
  2. Initial state
  3. Action
  4. Assertions

  Separate these phases visually where appropriate.

  Bad:

  ```rust
  fn rejects_invalid_input() {
	  let dir = TestDir::new();
	  let path = dir.path().join("test");
	  std::fs::write(&path, "invalid").unwrap();
	  let result = process(&path);
	  assert!(result.is_err());
	  assert!(path.exists());
  }
  ```

  Good:

  ```rust
  fn rejects_invalid_input() {
	  let dir = TestDir::new();
	  let path = dir.path().join("test");

	  std::fs::write(&path, "invalid").unwrap();

	  let result = process(&path);

	  assert!(result.is_err());
	  assert!(path.exists());
  }
  ```

  Keep related assertions together. Do not separate every
  assertion merely because it is a separate statement.

  ## 4. Preserve Cohesion

  Blank lines should reveal logical structure, not fragment it.

  Bad:

  ```rust
  let width = rect.width();

  let height = rect.height();

  let area = width * height;
  ```

  Good:

  ```rust
  let width = rect.width();
  let height = rect.height();
  let area = width * height;
  ```

  Keep tightly coupled statements together, including:

  - Related variable declarations
  - Construction of a single value
  - Consecutive assertions about the same outcome
  - Small, cohesive transformations
  - Operations that form one conceptual step

  ## 5. Avoid Redundant Comments

  Prefer whitespace over comments that merely label obvious
  operations.

  Avoid:

  ```rust
  // Initialize variables
  let width = 10;
  let height = 20;

  // Calculate area
  let area = width * height;
  ```

  Comments should explain intent, invariants, assumptions,
  or non-obvious behavior.

  ## 6. Respect Existing Style

  - Preserve meaningful whitespace already present.
  - Follow established repository conventions.
  - Avoid gratuitous formatting changes to unrelated code.
  - Do not restructure correct code solely to introduce spacing.
  - Prefer small, reviewable diffs.

  ## 7. Completion Review

  After running rustfmt, inspect the final formatted source.

  For each newly written or substantially modified function:

  1. Identify its logical phases.
  2. Verify that phase boundaries are visually recognizable.
  3. Group related statements together.
  4. Remove distracting or excessive blank lines.
  5. Ensure adjacent functions are separated.
  6. Check that the final code is easy to scan and audit.

  Do not consider rustfmt compliance sufficient evidence of
  readability.

  A readability-only pass must preserve program behavior.

  If edits go beyond whitespace, rerun relevant verification.
