---
name: doc-advisor
description: Checks documentation completeness for Cangjie code
trigger: when reviewing code documentation
---

Apply these documentation standards when reviewing Cangjie code:
1. Every public class or struct must have a one-line doc comment stating its purpose.
2. Every public function must document what it returns (or state "returns Unit").
3. Any block of logic longer than 10 lines with non-obvious intent must have an inline comment explaining why, not what.
