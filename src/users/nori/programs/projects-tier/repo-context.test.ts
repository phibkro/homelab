import { afterAll, describe, expect, test } from "bun:test"
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import {
  CONTEXT_MESSAGE_TYPE,
  ChainTracker,
  type Injection,
  findRepoRoot,
  readChain,
  touchedPaths,
  typeScriptEdits,
} from "./repo-context.ts"

const root = realpathSync(mkdtempSync(join(tmpdir(), "projects-tier-")))
afterAll(() => rmSync(root, { recursive: true, force: true }))

function put(path: string, text: string): string {
  const absolute = join(root, path)
  mkdirSync(dirname(absolute), { recursive: true })
  writeFileSync(absolute, text)
  return absolute
}

const projects = join(root, "projects")
const app = join(projects, "group", "app")
const worktree = join(projects, "group", "app-wt")
const plain = join(projects, "plain")
const noHouse = join(projects, "no-house")
const outside = join(root, "outside")
const userInstructions = put("agent/AGENTS.md", "USER SOUL: partner, not assistant.\n")

put("projects/AGENTS.md", "PROJECTS TIER RULES\n")
// Like /srv/share/projects/.git: a .git directory without HEAD is not a repository.
put("projects/.git/info/exclude", "")
put("projects/group/AGENTS.md", "GROUP RULES\n")
put("projects/group/app/.git/HEAD", "ref: refs/heads/main\n")
put("projects/group/app/AGENTS.md", "APP RULES\n")
put("projects/group/app/src/main.ts", "export const main = 1\n")
put(
  "projects/group/app/.agents/skills/effect-house/SKILL.md",
  "---\nname: effect-house\ndescription: House conventions. Use when writing Effect code here.\n---\n\nHOUSE RULES: see references/constructs.md.\n",
)
put(
  "projects/group/app/.agents/skills/release/SKILL.md",
  "---\nname: release\ndescription: >-\n  Release procedure.\n  Use when cutting a release.\n---\n\nSteps.\n",
)
put("projects/group/app-wt/.git", `gitdir: ${app}/.git/worktrees/app-wt\n`)
put("projects/group/app-wt/AGENTS.md", "APP RULES\n")
put("projects/plain/lib/x.ts", "export {}\n")
put("projects/no-house/.git/HEAD", "ref: refs/heads/main\n")
put("projects/no-house/AGENTS.md", "NO HOUSE RULES\n")
put("outside/.git/HEAD", "ref: refs/heads/main\n")
put("outside/AGENTS.md", "OUTSIDE RULES\n")

function tracker(): ChainTracker {
  return new ChainTracker({ projectsRoot: projects, userInstructions })
}

const noContext = (): string => ""

/** An injection as it appears in the model context: a custom message carrying the hook's details. */
function inContext(injection: Injection | undefined): unknown {
  return { role: "custom", customType: CONTEXT_MESSAGE_TYPE, content: injection?.text, details: injection?.details }
}

const hashline = (...lines: string[]): { input: string } => ({ input: lines.join("\n") })

describe("touchedPaths", () => {
  test("resolves file references against the working directory and drops selectors", () => {
    expect(touchedPaths("read", { path: "src/main.ts:10-20" }, app)).toEqual([join(app, "src/main.ts")])
    expect(touchedPaths("write", { path: "/abs/file.ts", content: "" }, app)).toEqual(["/abs/file.ts"])
  })

  test("ignores internal URIs and unknown tools", () => {
    expect(touchedPaths("read", { path: "skill://effect-first" }, app)).toEqual([])
    expect(touchedPaths("write", { path: "local://notes.md", content: "" }, app)).toEqual([])
    expect(touchedPaths("bash", { command: "cat src/main.ts" }, app)).toEqual([])
    expect(touchedPaths("read", null, app)).toEqual([])
    expect(touchedPaths("grep", 42, app)).toEqual([app])
  })

  test("uses the glob-free prefix of every search root", () => {
    expect(touchedPaths("grep", { pattern: "x", path: "src; tests/**/*.ts" }, app)).toEqual([
      join(app, "src"),
      join(app, "tests"),
    ])
    expect(touchedPaths("glob", { path: "**/*.ts" }, app)).toEqual([app])
    expect(touchedPaths("grep", { pattern: "x" }, app)).toEqual([app])
  })

  test("reads hashline sections and move destinations, not body rows", () => {
    const input = hashline(
      "*** Begin Patch",
      "[src/a.ts#1A2B]",
      "PUT 1.=1:",
      "+[src/not-a-target.ts#0000]",
      'MV "src/renamed file.ts"',
      "[README.md#3c4d]",
      "REM",
      "*** End Patch",
    )
    expect(touchedPaths("edit", input, app)).toEqual([
      join(app, "src/a.ts"),
      join(app, "src/renamed file.ts"),
      join(app, "README.md"),
    ])
  })

  test("reads apply_patch file markers, not context rows", () => {
    const input = hashline(
      "*** Begin Patch",
      "*** Add File: src/new.ts",
      "+export {}",
      "*** Update File: src/old.ts",
      "*** Move to: src/moved.ts",
      "@@",
      " [src/context-line.ts#1A2B]",
      "*** Delete File: docs/gone.md",
      "*** End Patch",
    )
    const expected = ["src/new.ts", "src/old.ts", "src/moved.ts", "docs/gone.md"].map((path) => join(app, path))
    expect(touchedPaths("edit", input, app)).toEqual(expected)
    expect(touchedPaths("apply_patch", input, app)).toEqual(expected)
  })

  test("reads the path and renames of the replace and patch edit modes", () => {
    expect(touchedPaths("edit", { path: "src/a.ts", old_string: "a", new_string: "b" }, app)).toEqual([
      join(app, "src/a.ts"),
    ])
    expect(touchedPaths("edit", { path: "src/a.ts", edits: [{ op: "update", rename: "src/b.ts" }] }, app)).toEqual([
      join(app, "src/a.ts"),
      join(app, "src/b.ts"),
    ])
  })

  test("reads structural search and rewrite targets, including the xd:// devices", () => {
    expect(touchedPaths("write", { path: "xd://ast_grep", content: '{"pat":"x","path":"src/**/*.ts"}' }, app)).toEqual([
      join(app, "src"),
    ])
    expect(touchedPaths("ast_edit", { ops: [], paths: ["src/main.ts"] }, app)).toEqual([join(app, "src/main.ts")])
    expect(touchedPaths("write", { path: "xd://ast_grep", content: "not json" }, app)).toEqual([])
  })
})

describe("typeScriptEdits", () => {
  test("names TypeScript files that a call changes and nothing that only reads", () => {
    expect(typeScriptEdits("write", { path: "src/main.ts", content: "" }, app)).toEqual([join(app, "src/main.ts")])
    expect(typeScriptEdits("write", { path: "README.md", content: "" }, app)).toEqual([])
    expect(typeScriptEdits("edit", hashline("[src/view.tsx#1A2B]", "PUT 1.=1:", "+x", "[README.md#1A2B]", "REM"), app)).toEqual([
      join(app, "src/view.tsx"),
    ])
    expect(typeScriptEdits("edit", { path: "README.md", old_string: "a", new_string: "b" }, app)).toEqual([])
    expect(typeScriptEdits("read", { path: "src/main.ts" }, app)).toEqual([])
    expect(typeScriptEdits("write", { path: "xd://ast_grep", content: '{"pat":"x","path":"src/main.ts"}' }, app)).toEqual(
      [],
    )
  })

  test("treats a structural rewrite of TypeScript as an edit of its roots", () => {
    expect(typeScriptEdits("ast_edit", { ops: [], paths: ["src/**/*.ts"] }, app)).toEqual([join(app, "src")])
    expect(typeScriptEdits("write", { path: "xd://ast_edit", content: '{"ops":[],"paths":["src"],"lang":"typescript"}' }, app)).toEqual([
      join(app, "src"),
    ])
    expect(typeScriptEdits("ast_edit", { ops: [], paths: ["docs/**/*.md"] }, app)).toEqual([])
  })
})

describe("findRepoRoot", () => {
  test("finds the toplevel of an existing or not-yet-created path", () => {
    expect(findRepoRoot(join(app, "src/main.ts"))).toBe(app)
    expect(findRepoRoot(join(app, "src/new/dir/file.ts"))).toBe(app)
  })

  test("treats a worktree's .git file as its toplevel", () => {
    expect(findRepoRoot(join(worktree, "src/main.ts"))).toBe(worktree)
  })

  test("does not treat a .git directory without HEAD as a repository", () => {
    expect(findRepoRoot(join(plain, "lib/x.ts"))).toBeUndefined()
  })

  test("agrees with git rev-parse for a real linked worktree", () => {
    const repo = join(root, "real")
    mkdirSync(repo)
    const git = (cwd: string, ...args: string[]): string => {
      const run = Bun.spawnSync(["git", "-c", "user.name=t", "-c", "user.email=t@t", ...args], { cwd })
      if (run.exitCode !== 0) throw new Error(`git ${args.join(" ")}: ${run.stderr.toString()}`)
      return run.stdout.toString().trim()
    }
    git(repo, "init", "--quiet")
    git(repo, "commit", "--quiet", "--allow-empty", "-m", "init")
    git(repo, "worktree", "add", "--quiet", "--detach", join(root, "real-wt"))
    const nested = join(root, "real-wt", "a", "b")
    mkdirSync(nested, { recursive: true })
    expect(findRepoRoot(join(nested, "file.ts"))).toBe(git(nested, "rev-parse", "--show-toplevel"))
    expect(findRepoRoot(join(repo, "file.ts"))).toBe(git(repo, "rev-parse", "--show-toplevel"))
  })
})

describe("readChain", () => {
  test("collects AGENTS.md from the projects root down to the repository", () => {
    const chain = readChain(app, projects)
    expect(chain.files.map((file) => file.path)).toEqual([
      join(projects, "AGENTS.md"),
      join(projects, "group", "AGENTS.md"),
      join(app, "AGENTS.md"),
    ])
    expect(chain.skills.map((skill) => [skill.name, skill.description])).toEqual([
      ["effect-house", "House conventions. Use when writing Effect code here."],
      ["release", "Release procedure. Use when cutting a release."],
    ])
    expect(chain.house?.text).toContain("HOUSE RULES")
  })

  test("reads no ancestors for a repository outside the projects root", () => {
    const chain = readChain(outside, projects)
    expect(chain.files.map((file) => file.path)).toEqual([join(outside, "AGENTS.md")])
    expect(chain.house).toBeUndefined()
  })
})

describe("ChainTracker", () => {
  const readMain = { path: join(app, "src/main.ts") }
  const writeMain = { path: join(app, "src/main.ts"), content: "export const main = 2\n" }

  test("injects a repository's chain once per session", () => {
    const session = tracker()
    const first = session.onToolCall("read", readMain, app, noContext)
    expect(first.injections.map((injection) => injection.details.repo)).toEqual([app])
    expect(session.onToolCall("grep", { pattern: "x", path: join(app, "src") }, app, noContext).injections).toEqual([])
    const other = session.onToolCall("read", { path: join(noHouse, "AGENTS.md") }, app, noContext)
    expect(other.injections.map((injection) => injection.details.repo)).toEqual([noHouse])
  })

  test("subagent session receives chain on first touch", () => {
    // A task subagent's system prompt holds no AGENTS.md (OMP filters them out).
    const [injection] = tracker().onToolCall("read", readMain, app, noContext).injections
    expect(injection?.details.included).toEqual([
      userInstructions,
      join(projects, "AGENTS.md"),
      join(projects, "group", "AGENTS.md"),
      join(app, "AGENTS.md"),
    ])
    const text = injection?.text ?? ""
    for (const expected of ["USER SOUL", "PROJECTS TIER RULES", "GROUP RULES", "APP RULES", "HOUSE RULES", "`release`"]) {
      expect(text).toContain(expected)
    }
    // General first, repository last: the more specific file wins.
    expect(text.indexOf("USER SOUL")).toBeLessThan(text.indexOf("PROJECTS TIER RULES"))
    expect(text.indexOf("GROUP RULES")).toBeLessThan(text.indexOf("APP RULES"))
  })

  test("a main session gets only what its context walk missed", () => {
    // OMP renders each context file in a <file path> element, whitespace normalized and
    // imports expanded: the user file is found by its marker, the app file by its text.
    const systemPrompt = (): string =>
      `<repo-rules>\n<file path="${userInstructions}">\nUSER SOUL (rendered with expanded imports)\n</file>\n</repo-rules>\n<other>APP\n\n\nRULES</other>`
    const [injection] = tracker().onToolCall("read", readMain, app, systemPrompt).injections
    expect(injection?.details.included).toEqual([join(projects, "AGENTS.md"), join(projects, "group", "AGENTS.md")])
    expect(injection?.text).not.toContain("USER SOUL")
    expect(injection?.text).toContain(`- ${join(app, "AGENTS.md")}`)
  })

  test("offers the user AGENTS.md to the first injection only", () => {
    const session = tracker()
    session.onToolCall("read", { path: join(app, "AGENTS.md") }, app, noContext)
    const [second] = session.onToolCall("read", { path: join(outside, "AGENTS.md") }, app, noContext).injections
    expect(second?.details.included).toEqual([join(outside, "AGENTS.md")])
  })

  test("holds back a TypeScript edit in an effect-house repository until delivery", () => {
    const session = tracker()
    const first = session.onToolCall("write", writeMain, app, noContext)
    expect(first.injections).toHaveLength(1)
    expect(first.block).toContain(app)
    const retryTooEarly = session.onToolCall("write", writeMain, app, noContext)
    expect(retryTooEarly.injections).toEqual([])
    expect(retryTooEarly.block).toBeDefined()
    expect(session.onToolCall("write", { path: join(app, "README.md"), content: "" }, app, noContext).block).toBeUndefined()
    session.onMessage({ role: "custom", customType: "other-extension", details: { repo: app } })
    expect(session.onToolCall("write", writeMain, app, noContext).block).toBeDefined()
    session.onMessage(inContext(first.injections[0]))
    expect(session.onToolCall("write", writeMain, app, noContext).block).toBeUndefined()
  })

  test("a context that carries the injection opens the gate, details or not", () => {
    const session = tracker()
    const [injection] = session.onToolCall("edit", hashline("[src/main.ts#1A2B]", "PUT 1.=1:", "+x"), app, noContext).injections
    // A host that drops custom details still shows the heading the hook wrote.
    session.onContext([{ role: "user", content: "hi" }, { customType: CONTEXT_MESSAGE_TYPE, content: [{ type: "text", text: injection?.text }] }])
    expect(session.onToolCall("write", writeMain, app, noContext).block).toBeUndefined()
  })

  test("does not gate repositories without effect-house, nor reads", () => {
    const session = tracker()
    const write = session.onToolCall("write", { path: join(noHouse, "src/x.ts"), content: "" }, noHouse, noContext)
    expect(write.injections).toHaveLength(1)
    expect(write.block).toBeUndefined()
    expect(session.onToolCall("read", readMain, app, noContext).block).toBeUndefined()
  })

  test("opens the gate when the injection has not arrived one full turn later", () => {
    const session = tracker()
    expect(session.onToolCall("write", writeMain, app, noContext).block).toBeDefined()
    session.onTurnStart()
    expect(session.onToolCall("write", writeMain, app, noContext).block).toBeDefined()
    session.onTurnStart()
    expect(session.onToolCall("write", writeMain, app, noContext).block).toBeUndefined()
  })

  test("a context that dropped the injection re-arms injection and the gate", () => {
    const session = tracker()
    const [injection] = session.onToolCall("write", writeMain, app, noContext).injections
    session.onContext([inContext(injection)])
    expect(session.onToolCall("write", writeMain, app, noContext)).toEqual({ injections: [], block: undefined })
    // Compaction or /clear: the next context no longer holds the injection.
    session.onContext([{ role: "compactionSummary", summary: "earlier work" }])
    const again = session.onToolCall("write", writeMain, app, noContext)
    expect(again.injections.map((next) => next.details.repo)).toEqual([app])
    expect(again.injections[0]?.details.included).toContain(userInstructions)
    expect(again.block).toBeDefined()
  })

  test("an injection never seen in context is not injected again", () => {
    const session = tracker()
    const [injection] = session.onToolCall("read", readMain, app, noContext).injections
    // A host that folds asides into other messages delivers without showing the custom message.
    session.onMessage(inContext(injection))
    session.onContext([{ role: "user", content: "folded" }])
    expect(session.onToolCall("read", readMain, app, noContext).injections).toEqual([])
  })

  test("a resumed session recovers its injections from the context", () => {
    const [earlier] = tracker().onToolCall("read", readMain, app, noContext).injections
    const resumed = tracker()
    resumed.onContext([inContext(earlier)])
    expect(resumed.onToolCall("write", writeMain, app, noContext)).toEqual({ injections: [], block: undefined })
    // The user AGENTS.md came with the earlier injection, so a new repository does not repeat it.
    const [next] = resumed.onToolCall("read", { path: join(outside, "AGENTS.md") }, app, noContext).injections
    expect(next?.details.included).toEqual([join(outside, "AGENTS.md")])
  })

  test("touches outside any repository inject nothing", () => {
    const plan = tracker().onToolCall("write", { path: join(plain, "lib/x.ts"), content: "" }, plain, noContext)
    expect(plan).toEqual({ injections: [], block: undefined })
  })
})
