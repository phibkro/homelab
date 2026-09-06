---
name: writing-python
description: |
  Write or review Python that is idiomatic, fast, and hard to get wrong. Use
  when writing new Python, reviewing a diff, refactoring a loop-heavy or
  dict-heavy function, choosing a data structure, or setting up ruff for a
  repository. Also use when the user says "idiomatic Python", "pythonic",
  "clean this up", "Hettinger", "make this faster", "why is this slow", or
  asks which ruff rules to enable. Encodes Raymond Hettinger's "Transforming
  Code into Beautiful, Idiomatic Python" plus the ruff rules that enforce it
  and the ones that cannot.
license: MIT
metadata:
  version: "1.0.0"
  compatibility: "claude-code cursor codex gemini-cli opencode"
  sources: >
    Raymond Hettinger, PyCon US 2013 (video youtube.com/watch?v=OSGv2VnC0go);
    ruff 0.16 rule set, measured 2026-08-02
---

# Writing Python: idiomatic, fast, hard to get wrong

One rule sits above the rest: **one logical line of code equals one sentence
in English.** Do not put too much on one line, and do not break atoms of
thought into subatomic particles.

Two efficiency laws under it:

- Do not move data around unnecessarily.
- It takes only a little care to avoid O(n²) where O(n) was available.

## The transformations

Each row is a pattern to remove and what replaces it. The right-hand column
says whether a linter can catch it for you — that decides whether you must
watch for it by eye. Rule codes are ruff's, verified against 0.16.

### Looping

| Instead of | Write | Caught by |
|---|---|---|
| `for i in range(len(c)): c[i]` | `for x in c:` | **nothing — watch by eye** |
| `for i in range(len(c)-1,-1,-1)` | `for x in reversed(c):` | nothing |
| `for i in range(len(c)): i, c[i]` | `for i, x in enumerate(c):` | nothing (pylint C0200 is unported) |
| index-parallel lists | `for a, b in zip(xs, ys, strict=True):` | nothing |
| manual counter `i += 1` | `enumerate` | SIM113 |
| `c[i]` inside `enumerate` | use the bound value | PLR1736 |
| `sorted(c, cmp=f)` | `sorted(c, key=f)` | removed in py3 |
| `while True: … if x: break` | `for x in iter(partial(f.read, 32), b''):` | nothing |
| a `found` flag around a loop | `for … else:` | nothing |

**Whenever you find yourself manipulating indices into a collection, you are
probably doing it wrong.** `zip(..., strict=True)` is the modern addition to
the talk: it turns a silent truncation into an error.

### Dicts

| Instead of | Write | Caught by |
|---|---|---|
| `for k in d: d[k]` | `for k, v in d.items():` | **PLC0206** |
| `if k in d: d[k]=0` then `+=1` | `Counter(items)` or `d.get(k,0)+1` | nothing |
| `if k not in d: d[k]=[]` then append | `defaultdict(list)` or `d.setdefault(k,[])` | nothing |
| `d.copy()` then `.update()` chains | `ChainMap(cli, env, defaults)` | nothing |
| `k in d.keys()` | `k in d` | SIM118 |

Mutating a dict while iterating it is undefined behavior in practice.
Iterate `list(d.keys())` when you intend to delete.

### Structures and clarity

| Instead of | Write | Caught by |
|---|---|---|
| `f(a, False, 20, True)` | `f(a, retweets=False, numtweets=20)` | nothing |
| returning a bare tuple | `NamedTuple` / `@dataclass` | nothing |
| `x=p[0]; y=p[1]` | `x, y = p` | nothing |
| `t=y; y=x+y; x=t` | `x, y = y, x + y` | nothing |
| staged temp vars for one state step | one simultaneous tuple assignment | nothing |

State should update all at once. Between two of those lines the object is
inconsistent, and ordering bugs live exactly there.

### Efficiency

| Instead of | Write | Caught by |
|---|---|---|
| `s += ', ' + name` in a loop | `', '.join(names)` | nothing |
| `list.pop(0)` / `insert(0, x)` | `collections.deque` | nothing |
| `result=[]` + `append` in a loop | a comprehension | **PERF401** |
| the same for a dict | a dict comprehension | **PERF403** |
| `sum([x for x in it])` | `sum(x for x in it)` | C4xx |

`pop(0)` and `insert(0, …)` on a list are signs you chose the wrong data
structure; both are O(n).

### Context managers and decorators

They separate business logic from administrative logic. Good naming is
essential; with great power comes great responsibility.

| Instead of | Write | Caught by |
|---|---|---|
| `try/finally: f.close()` | `with open(...) as f:` | **SIM115** |
| `lock.acquire()` / `try` / `release` | `with lock:` | nothing |
| `try: … except OSError: pass` | `with contextlib.suppress(OSError):` | **SIM105** |
| save/restore a global | `contextlib.redirect_stdout`, a custom `@contextmanager` | nothing |
| hand-rolled memo dict | `@functools.cache` | nothing |

## Enforcement: what ruff does and does not do

**Ruff has no plugin API.** There is no way to add a custom rule short of
forking it. Verified on 0.16: no `--plugin`, no `extend-rule`.

Measured coverage: ruff has 968 rules and implements roughly **40 percent**
of the patterns above. It reliably catches the comprehension, context
manager, and `dict.items()` families. It catches **none** of the
`range(len(...))` loop rewrites — the most famous item in the talk.

So: enable the rules, then read for the rest.

```toml
[tool.ruff.lint]
select = [
  "E", "F", "W",       # correctness basics
  "B",                 # bugbear traps
  "UP",                # modern syntax
  "I",                 # import order
  "SIM",               # simplifications that remove bug surface
  "PERF",              # manual loops that should be comprehensions
  "C4",                # comprehension and call simplification
  "FURB",              # refurb modernizations
  "PTH",               # pathlib over os.path string handling
  "RET", "PIE", "ISC", # return flow, dead code, implicit concat
  "DTZ",               # naive datetimes
  "PLC0206", "PLR1736", "PLW2901", "SIM113", "SIM118",
]
```

`PL*` and `RUF` as whole families are noisy — mostly magic-number rules.
Select the members you want by code, as above.

**Make every exception explicit.** An ignored rule needs its reason next to
it, or it becomes folklore:

```toml
ignore = [
  # PTH123 rewrites open(p) as Path(p).open(): longer, no safer, and these
  # are scripts that already hold a Path. The rest of PTH stays ON.
  "PTH123",
]
```

Per-line, the same discipline — say why, not just what:

```python
# submissions.json records LOCAL time and naive .astimezone() converts from
# the system zone, which is what we want here.
local = datetime.strptime(rec["date"], "%Y-%m-%d %H:%M:%S")  # noqa: DTZ007
```

## For the patterns ruff cannot see

Write them as a small AST check in the repository, using Python's own `ast`
module. It is the reference parser, it always matches the running language
version, and it needs no dependency. A third-party grammar in another
language can disagree with CPython — which is a two-copies-can-disagree bug
inside the tool meant to prevent them.

Each rule must cite the incident that motivated it. **A lint rule with no
failure behind it is cargo cult and should be deleted.**

## Review checklist

1. Any `range(len(...))`? Replace with iteration, `enumerate`, or `zip`.
2. Any index arithmetic into a collection? Probably wrong.
3. Any accumulation in a loop that a comprehension or `join` would do?
4. Any `pop(0)` or `insert(0, …)`? Use a `deque`.
5. Any `try/finally` restoring state? Use a context manager.
6. Any positional boolean argument? Name it.
7. Any bare tuple return with more than two fields? Name it.
8. Any dict iterated by key and re-indexed? Use `.items()`.
9. Any staged temporaries for one state update? One tuple assignment.
10. Is each line one sentence of English?
