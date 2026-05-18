---
name: complexity-limits
description: Enforces function complexity limits for Cangjie code
trigger: when reviewing function complexity
---

Apply these complexity limits when reviewing Cangjie code:
1. No function body may exceed 50 lines (excluding blank lines and comments).
2. Nesting depth must not exceed 4 levels (if, for, match, and try combined).
3. A single function must not perform more than one distinct responsibility.
