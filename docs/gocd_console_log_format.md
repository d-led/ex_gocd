# GoCD Console Log Format — Source Analysis & Implementation Guide

## Source references
All findings from `/Users/dmitryledentsov/src/gocd-rewrite/gocd` (GoCD OSS).

---

## 1. Tagged Stream Format

GoCD uses a **two-character tag prefix** on every console line:

```
TAG|HH:mm:ss.SSS message text
```

### Tag constants (from `TaggedStreamConsumer.java`)

| Tag  | Constant           | Meaning                  |
|------|--------------------|--------------------------|
| `##` | NOTICE             | System notice / stage marker |
| `!!` | TASK_START         | Task begins              |
| `?0` | TASK_PASS          | Task passed              |
| `?1` | TASK_FAIL          | Task failed              |
| `^C` | TASK_CANCELLED     | Task cancelled           |
| `!x` | CANCEL_TASK_START  | On-cancel task begins    |
| `x0` | CANCEL_TASK_PASS   | On-cancel task passed    |
| `x1` | CANCEL_TASK_FAIL   | On-cancel task failed    |
| `&1` | OUT                | stdout from command      |
| `&2` | ERR                | stderr from command      |
| `pr` | PREP               | Preparation phase        |
| `pe` | PREP_ERR           | Preparation error        |
| `ar` | PUBLISH            | Artifact publish         |
| `ae` | PUBLISH_ERR        | Artifact publish error   |
| `j0` | JOB_PASS           | Job passed summary       |
| `j1` | JOB_FAIL           | Job failed summary       |
| `ex` | COMPLETED          | Job completed            |

### Timestamp format (from `ConsoleOutputTransmitter.java`)
```java
DateTimeFormatter.ofPattern("HH:mm:ss.SSS")  // 24-hour, local time
LocalTime.now()                               // local timezone, NOT UTC
```

### Full format examples:
```
!!|08:15:20.141 Task: git clone https://github.com/...
&1|08:15:21.000 Cloning into 'repo'...
&2|08:15:21.500 warning: redirecting to ...
?0|08:15:22.000 Task: git clone (exit code: 0)
&1|08:15:22.001 ##[notice] some notice
j0|08:15:30.000 Job completed
```

### NOTICE messages use `[go]` prefix:
```java
taggedConsumeLineWithPrefix(NOTICE, message);
// produces: ##|HH:mm:ss.SSS [go] message text
```

---

## 2. Task Boundaries (Collapsible Sections)

GoCD wraps each build task with start/pass/fail tags:

```
!!|08:15:20.141 Task: git clone https://github.com/d-led/ex_gocd
  ... task output (stdout &1|, stderr &2|) ...
?0|08:15:22.000 Task: git clone (exit code: 0)     ← passed
?1|08:15:22.000 Task: mix test (exit code: 1)       ← failed
```

The GoCD UI renders each `!!` / `?0` pair as a **collapsible section**.
The section name is the text after `Task: ` in the `!!` line.
The section collapses/expands via client-side JS.

### Key: Task status always emitted, even if empty
```java
// From Builders.java
goPublisher.taggedConsumeLineWithPrefix(TASK_START, executeMessage);
builder.build(...);
goPublisher.taggedConsumeLineWithPrefix(tag, statusLine);
```

---

## 3. Stderr Stream Handling

Stderr is captured by `StreamPumper` with `"stderr: "` prefix and fed to `ERR` tag:
```java
// stdout → taggedConsumeLine(OUT, line)
// stderr → taggedConsumeLine(ERR, "stderr: " + line)  with prefix
```

Then `ConsoleOutputTransmitter` prepends the tag:
```
&2|08:15:21.500 stderr: warning text
```

The `"stderr: "` prefix in the message body is the **GoCD convention**.

---

## 4. Console Output Flow (Agent Side)

```
Builders.java
  └─ goPublisher.taggedConsumeLineWithPrefix(TASK_START, "Task: name")
       └─ CommandLine.java
            └─ StreamPumper (stdout → OUT, stderr → ERR prefix)
                 └─ DefaultGoPublisher.taggedConsumeLine(tag, line)
                      └─ ConsoleOutputTransmitter.taggedConsumeLine(tag, line)
                           └─ format("%s|%s %s", tag, HH:mm:ss.SSS, line)
                                └─ buffer + flush to server
```

---

## 5. UI Rendering

### Server-side tags → collapsible sections
The GoCD server parses the tag prefixes from console lines:
- `!!` / `?0` → fold section boundaries (task start / task pass)
- `!!` / `?1` → fold section boundaries (task start / task fail, shown in red)
- `&1` → normal output (stdout)
- `&2` → stderr output (shown with error styling)
- `##` → system notices (shown with `[go]` prefix)

### ANSI color support
The GoCD UI supports ANSI escape codes in console output:
- `\e[32m` → green text
- `\e[31m` → red text
- etc.

---

## 6. What Our Implementation Does

### Current (before this doc)
| Aspect          | GoCD                    | Our ex_gocd           |
|-----------------|-------------------------|------------------------|
| Tag format      | `&1\|HH:mm:ss.SSS text`  | `HH:mm:ss.SSS text`   |
| Stderr prefix   | `&2\|... stderr: text`   | `HH:mm:ss.SSS stderr: text` |
| Task boundaries | `!!\|... Task: name`     | `HH:mm:ss.SSS ##[fold]name` |
| Task end        | `?0\|... Task: name`     | `HH:mm:ss.SSS ##[endfold]`  |
| Timestamp tz    | Local time             | Local time (`time.Now()`) |
| ANSI colors     | Supported              | Supported (via ConsoleLogHelper) |

### Gaps
1. **No GoCD tag format** — we use `##[fold]`/`##[endfold]` instead of `!!`/`?0`
2. **Stderr prefix inconsistent** — GoCD uses tag-level `&2` + message-level `stderr:`, we only use message-level `stderr:`
3. **`[go]` notice prefix** — GoCD uses `##|[go] message`, we don't have system notices

### Recommendation
The current `##[fold]`/`##[endfold]` approach is simpler and works well for the UI.
The GoCD tag format could be adopted later for full parity, but the UX is equivalent.
The critical gaps are already covered: folds, ANSI colors, stderr prefix, local timestamps.
