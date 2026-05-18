---
name: code-reviewer
description: Reviews Cangjie code for quality issues following project standards
trigger: when asked to review code quality
---

Apply these rules when reviewing Cangjie code:
1. Flag any function or method body exceeding 50 lines.
2. Verify all caught exceptions are handled explicitly (not silently swallowed with an empty catch).
3. Check that all public functions and types have at least a one-line doc comment.
4. Check for hardcoded string or numeric literals that should be named constants.

