# Discussion Questions

## Q1: Scope — what is this a feature *of*?

The doc is framed generally, but it's landing in Magic CLI. Is this:

- (a) A way to test **Magic CLI itself** — e.g., you change `CangjieCodeAgent`'s system prompt and want to replay a benchmark task to see how behavior diverges?
- (b) A feature Magic CLI **provides to users** so they can test their own agent configurations (custom agents, skills, AGENTS.md tweaks)?

The answer shapes almost everything — where recording hooks in, what a "task" is, where traces live.

**A:**

More precesely, I want this to be a way to test general agent systems. But currently, I am just doing initial study. So Let's choose (a). 

---

## Q2: Integration point — where does recording hook in?

The current executor is the `tool-loop:1000` machinery inside the `@agent` decorator. Recording needs to wrap that loop. Is the expectation:

- (a) A new executor mode, e.g. `"tool-loop-record:1000"` / `"tool-loop-replay:1000"`?
- (b) A separate CLI entry point, e.g. `--mode record` / `--mode replay`?
- (c) Something else entirely?

**A:**

Let's say (b)

---

## Q3: What counts as a "task"?

In the current CLI, a user types a prompt and the agent iterates until done. Is a "task":

- (a) One such prompt + response cycle (single turn)?
- (b) A full multi-turn session?
- (c) Something defined more explicitly — e.g., a test file with a prompt + expected outcome?

**A:**

As an initial study, I think we go with (a). But this is a good question. Let's also put this into the design.md, saying that to begin with, we focus on a single prompt + response cycle. But in the future, we can add more options.

---

## Q4: System prompt stability

The current system prompt can include dynamic content — AGENTS.md from the working directory, possibly dates or file paths. Could the hash shift between runs even without intentional edits? Should the comparison be strict byte equality, or is there a normalization step planned?

**A:**

Let's first regard the system prompt as static. But flag this as a question for later. Maybe make a todo.md and put it there. A quick thought is that show the users which part of the system prompt has changed and let the users to decide whether these changes are on purpose. But if you have better ideas, please share.

---

## Q5: Stage priority

The roadmap says Stage 1 (single agent, manual environment reset) is the "entire core." Is that the target for the first implementation — leaving the multi-agent DAG and sandboxing for later?

**A:**
Let's put the sandboxing for later. You can try to design the multi-agent things now. Take the answer in Q6 as reference.

Help me make sure that in this project, the only multi-agent thing is `AgentAsTool()`, right?

---

## Q6: Sub-agent trace granularity

The current architecture wraps sub-agents as tools via `AgentAsTool(...)`. From the parent agent's perspective, calling a sub-agent looks just like calling any other tool — it has inputs and a result. Should the trace treat a sub-agent call as an opaque tool call (record only the final result), or should it record the sub-agent's internal steps too?

**A:**

We can currently Record it as sub-agent. Because sub-agent can also call tools, though it is treated as a tool of the main agent.
