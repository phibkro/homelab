/**
 * Core of the projects-tier repository-context hook, kept free of OMP types so
 * it can be tested directly.
 *
 * OMP stops its context walk at the repository root, discovers repository
 * skills only when the working directory is inside the repository, and gives
 * task subagents no AGENTS.md at all. The hook closes that gap: the first time
 * a session touches a repository through a file tool, it injects the
 * repository's instruction chain once, and in a repository with an
 * `effect-house` overlay it holds back TypeScript edits until that injection
 * has reached the model. Whether an injection is still in the model's context
 * is read from that context, so compaction, `/clear`, branching, and resuming
 * need no bookkeeping of their own.
 */
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path"

export const CONTEXT_MESSAGE_TYPE = "projects-tier:repo-context"
export const PROJECTS_ROOT = "/srv/share/projects"
export const OVERLAY_SKILL = "effect-house"

const INSTRUCTION_FILE = "AGENTS.md"
const HEADING_PREFIX = "# Repository instructions: "
const SEARCH_ROOT_TOOLS: Record<string, true> = { grep: true, glob: true, ast_grep: true }
// `apply_patch` is the edit tool's wire name in apply_patch mode.
const EDIT_TOOLS: Record<string, true> = { edit: true, apply_patch: true }
const URI_SCHEME = /^[a-z][a-z0-9+.-]*:\/\//i
const GLOB_CHARACTERS = /[*?[\]{}]/
const TYPESCRIPT_FILE = /\.(?:ts|tsx|mts|cts)$/
// File markers of an edit payload, each at the start of a line: a hashline
// `[PATH#TAG]` section and its `MV DEST`, and the apply_patch
// `*** Add/Update/Delete File: PATH` and `*** Move to: PATH` lines.
const PAYLOAD_FILE_MARKERS = [
  /^\[(.+)#[0-9A-Fa-f]{4}\]$/,
  /^MV\s+(.+)$/,
  /^\*\*\* (?:Add|Update|Delete) File: (.+)$/,
  /^\*\*\* Move to: (.+)$/,
]
/** Agent turns after the injection during which an undelivered injection still holds TypeScript edits. */
const GATE_TURNS = 1

export interface ChainFile {
  readonly path: string
  readonly text: string
}

export interface RepoSkill {
  readonly name: string
  readonly description: string
  readonly path: string
}

export interface RepoChain {
  readonly repo: string
  /** Instruction files from the most general ancestor to the repository's own. */
  readonly files: readonly ChainFile[]
  readonly skills: readonly RepoSkill[]
  readonly house: ChainFile | undefined
}

export interface InjectionDetails {
  readonly repo: string
  /** Files whose full text the injection carries. */
  readonly included: readonly string[]
  readonly house: boolean
  /** The injection accounts for the user AGENTS.md (carries it, or names it as already in context). */
  readonly user: boolean
}

export interface Injection {
  readonly text: string
  readonly details: InjectionDetails
}

export interface ToolCallPlan {
  readonly injections: readonly Injection[]
  readonly block: string | undefined
}

function field(input: unknown, key: string): unknown {
  return typeof input === "object" && input !== null && key in input
    ? (input as Record<string, unknown>)[key]
    : undefined
}

function stringField(input: unknown, key: string): string | undefined {
  const value = field(input, key)
  return typeof value === "string" && value.trim() !== "" ? value.trim() : undefined
}

function listField(input: unknown, key: string): readonly unknown[] {
  const value = field(input, key)
  return Array.isArray(value) ? value : []
}

function stringList(input: unknown, key: string): string[] {
  return listField(input, key).filter((entry): entry is string => typeof entry === "string")
}

function readText(path: string): string | undefined {
  try {
    return statSync(path).isFile() ? readFileSync(path, "utf8") : undefined
  } catch {
    return undefined
  }
}

function parseJson(text: string | undefined): unknown {
  try {
    return JSON.parse(text ?? "")
  } catch {
    return undefined
  }
}

function absolutePath(raw: string, cwd: string): string {
  const expanded = raw === "~" || raw.startsWith("~/") ? join(homedir(), raw.slice(1)) : raw
  return isAbsolute(expanded) ? resolve(expanded) : resolve(cwd, expanded)
}

/** A file reference as the read/write/edit tools accept it: drop `:selector` suffixes and URIs. */
function fileReference(raw: string, cwd: string): string | undefined {
  if (URI_SCHEME.test(raw)) return undefined
  const colon = raw.indexOf(":")
  const path = colon === -1 ? raw : raw.slice(0, colon)
  return path === "" ? undefined : absolutePath(path, cwd)
}

function fileReferences(raws: readonly string[], cwd: string): string[] {
  const paths = raws.flatMap((raw) => {
    const reference = fileReference(raw, cwd)
    return reference === undefined ? [] : [reference]
  })
  return [...new Set(paths)]
}

/** A search root: the longest glob-free prefix of each `;`-separated entry. */
function searchRoots(raw: string | undefined, cwd: string): string[] {
  if (raw === undefined) return [resolve(cwd)]
  return raw
    .split(";")
    .map((entry) => entry.trim())
    .filter((entry) => entry !== "" && !URI_SCHEME.test(entry))
    .map((entry) => {
      const withoutSelector = entry.replace(/:\d[\d,+-]*$/, "")
      const segments = withoutSelector.split("/")
      const firstGlob = segments.findIndex((segment) => GLOB_CHARACTERS.test(segment))
      const prefix = firstGlob === -1 ? withoutSelector : segments.slice(0, firstGlob).join("/")
      return absolutePath(prefix === "" ? "." : prefix, cwd)
    })
}

function astDevicePaths(content: string | undefined, cwd: string): string[] {
  const parsed = parseJson(content)
  if (parsed === undefined) return []
  const listed = stringList(parsed, "paths").flatMap((path) => searchRoots(path, cwd))
  const single = stringField(parsed, "path")
  // `ast_grep` takes `path` (default: the working directory); `ast_edit` takes `paths`.
  return single === undefined && listed.length > 0 ? listed : [...searchRoots(single, cwd), ...listed]
}

function unquote(text: string): string {
  const trimmed = text.trim()
  const quote = trimmed[0]
  return trimmed.length >= 2 && (quote === '"' || quote === "'") && trimmed.endsWith(quote)
    ? trimmed.slice(1, -1)
    : trimmed
}

/** Files named by an edit payload's markers; body and context rows never start with a marker. */
function payloadFiles(payload: string): string[] {
  return payload.split("\n").flatMap((raw) => {
    const line = raw.trimEnd()
    for (const marker of PAYLOAD_FILE_MARKERS) {
      const path = marker.exec(line)?.[1]
      if (path !== undefined) return [unquote(path)]
    }
    return []
  })
}

/**
 * Files an edit call names in each edit mode: the `input` payload (hashline,
 * apply_patch), or `path` plus `edits[].rename` (replace, patch).
 */
function editFiles(input: unknown): string[] {
  const payload = field(input, "input")
  const path = stringField(input, "path")
  const renames = listField(input, "edits").flatMap((entry) => {
    const rename = stringField(entry, "rename")
    return rename === undefined ? [] : [rename]
  })
  return [...(typeof payload === "string" ? payloadFiles(payload) : []), ...(path === undefined ? [] : [path]), ...renames]
}

/** Filesystem paths a file-tool call touches, as absolute paths. Unknown tools touch nothing. */
export function touchedPaths(toolName: string, input: unknown, cwd: string): string[] {
  if (toolName === "read") {
    const path = stringField(input, "path")
    return fileReferences(path === undefined ? [] : [path], cwd)
  }
  if (toolName === "write") {
    const path = stringField(input, "path")
    if (path === undefined) return []
    if (path.startsWith("xd://ast_grep") || path.startsWith("xd://ast_edit")) {
      return astDevicePaths(stringField(input, "content"), cwd)
    }
    return fileReferences([path], cwd)
  }
  if (Object.hasOwn(EDIT_TOOLS, toolName)) return fileReferences(editFiles(input), cwd)
  if (toolName === "ast_edit") return stringList(input, "paths").flatMap((path) => searchRoots(path, cwd))
  if (Object.hasOwn(SEARCH_ROOT_TOOLS, toolName)) return searchRoots(stringField(input, "path"), cwd)
  return []
}

function astEditsTypeScript(query: unknown): boolean {
  const language = stringField(query, "lang")
  const entries = [...(stringField(query, "path")?.split(";") ?? []), ...stringList(query, "paths")]
  return (
    (language !== undefined && /^(?:ts|tsx|typescript)$/i.test(language)) ||
    entries.some((entry) => /\.(?:ts|tsx|mts|cts)(?:$|[^a-z])/.test(entry))
  )
}

/**
 * The TypeScript files (or, for structural rewrites, the search roots) that a
 * call would change. Reads and searches change nothing.
 */
export function typeScriptEdits(toolName: string, input: unknown, cwd: string): string[] {
  if (Object.hasOwn(EDIT_TOOLS, toolName)) {
    return touchedPaths(toolName, input, cwd).filter((path) => TYPESCRIPT_FILE.test(path))
  }
  if (toolName === "ast_edit") return astEditsTypeScript(input) ? touchedPaths(toolName, input, cwd) : []
  if (toolName !== "write") return []
  const path = stringField(input, "path") ?? ""
  if (path.startsWith("xd://ast_edit")) {
    return astEditsTypeScript(parseJson(stringField(input, "content"))) ? touchedPaths(toolName, input, cwd) : []
  }
  if (URI_SCHEME.test(path)) return []
  return touchedPaths(toolName, input, cwd).filter((target) => TYPESCRIPT_FILE.test(target))
}

function isGitMarker(marker: string): boolean {
  try {
    const stats = statSync(marker)
    if (stats.isDirectory()) return existsSync(join(marker, "HEAD"))
    return stats.isFile() && readFileSync(marker, "utf8").startsWith("gitdir:")
  } catch {
    return false
  }
}

/**
 * The git toplevel that owns `path`: the nearest ancestor holding a `.git`
 * directory with a HEAD, or a `.git` file pointing elsewhere (worktree or
 * submodule). The path itself need not exist yet.
 */
export function findRepoRoot(path: string): string | undefined {
  let directory = resolve(path)
  for (;;) {
    try {
      if (statSync(directory).isDirectory()) break
      directory = dirname(directory)
      break
    } catch {
      const parent = dirname(directory)
      if (parent === directory) return undefined
      directory = parent
    }
  }
  for (;;) {
    if (isGitMarker(join(directory, ".git"))) return directory
    const parent = dirname(directory)
    if (parent === directory) return undefined
    directory = parent
  }
}

function isWithin(path: string, root: string): boolean {
  const offset = relative(root, path)
  return offset === "" || (offset !== ".." && !offset.startsWith(`..${sep}`) && !isAbsolute(offset))
}

function frontmatterOf(text: string): unknown {
  const match = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text)
  if (match === null) return undefined
  try {
    return Bun.YAML.parse(match[1] ?? "")
  } catch {
    return undefined
  }
}

function repoSkills(repo: string): RepoSkill[] {
  const directory = join(repo, ".agents", "skills")
  let entries: string[]
  try {
    entries = readdirSync(directory)
  } catch {
    return []
  }
  return entries
    .sort()
    .flatMap((entry) => {
      const path = join(directory, entry, "SKILL.md")
      const text = readText(path)
      if (text === undefined) return []
      const frontmatter = frontmatterOf(text)
      return [
        {
          name: stringField(frontmatter, "name") ?? entry,
          description: stringField(frontmatter, "description") ?? "",
          path,
        },
      ]
    })
}

/**
 * Reads a repository's instruction chain: every `AGENTS.md` from the projects
 * root down to the repository (ancestors only for repositories inside the
 * projects root), the repository's skills, and the `effect-house` overlay.
 */
export function readChain(repo: string, projectsRoot: string = PROJECTS_ROOT): RepoChain {
  const directories = [repo]
  if (repo !== projectsRoot && isWithin(repo, projectsRoot)) {
    for (let directory = dirname(repo); isWithin(directory, projectsRoot); directory = dirname(directory)) {
      directories.push(directory)
      if (directory === projectsRoot) break
    }
  }
  const files = directories.reverse().flatMap((directory) => {
    const path = join(directory, INSTRUCTION_FILE)
    const text = readText(path)
    return text === undefined ? [] : [{ path, text }]
  })
  const skills = repoSkills(repo)
  const overlay = skills.find((skill) => skill.name === OVERLAY_SKILL)
  const houseText = overlay === undefined ? undefined : readText(overlay.path)
  return {
    repo,
    files,
    skills,
    house: overlay === undefined || houseText === undefined ? undefined : { path: overlay.path, text: houseText },
  }
}

/**
 * Renders one injection. A file already in the session's system prompt is
 * named instead of repeated, so a main session gets what its context walk
 * missed and a task subagent gets the whole chain. OMP renders each context
 * file as `<file path="…">` with its whitespace normalized and `@` imports
 * expanded, so a file counts as present when its marker is there or when its
 * whitespace-collapsed text is.
 */
export function renderChain(chain: RepoChain, systemPrompt: string, userFile: ChainFile | undefined): Injection | undefined {
  const files = userFile === undefined ? chain.files : [userFile, ...chain.files]
  const collapse = (text: string): string => text.replace(/\s+/g, " ").trim()
  const prompt = collapse(systemPrompt)
  const included = files.filter(
    (file) =>
      collapse(file.text) !== "" &&
      !systemPrompt.includes(`<file path="${file.path}">`) &&
      !prompt.includes(collapse(file.text)),
  )
  const named = files.filter((file) => !included.includes(file))
  if (included.length === 0 && chain.skills.length === 0 && chain.house === undefined) return undefined
  const lines = [
    `${HEADING_PREFIX}${chain.repo}`,
    "",
    `This session touched \`${chain.repo}\` for the first time. The files below are its instruction chain, from the most general to the repository's own; where they conflict, the later, more specific file wins. Follow them for all work in this repository.`,
  ]
  for (const file of included) lines.push("", `## ${file.path}`, "", file.text.trim())
  if (named.length > 0) {
    lines.push("", "## Already in your context", "")
    for (const file of named) lines.push(`- ${file.path}`)
  }
  if (chain.skills.length > 0) {
    lines.push(
      "",
      `## Repository skills (${join(chain.repo, ".agents", "skills")})`,
      "",
      "Read a skill's SKILL.md before work it covers.",
      "",
    )
    for (const skill of chain.skills) lines.push(`- \`${skill.name}\`: ${skill.description} (${skill.path})`)
  }
  if (chain.house !== undefined) {
    lines.push(
      "",
      `## ${OVERLAY_SKILL} (full text of ${chain.house.path})`,
      "",
      "Read the references it links before writing code they cover.",
      "",
      chain.house.text.trim(),
    )
  }
  return {
    text: lines.join("\n"),
    details: {
      repo: chain.repo,
      included: included.map((file) => file.path),
      house: chain.house !== undefined,
      user: userFile !== undefined,
    },
  }
}

function contentText(content: unknown): string | undefined {
  if (typeof content === "string") return content
  const block = Array.isArray(content) ? content.find((entry) => field(entry, "type") === "text") : undefined
  const text = field(block, "text")
  return typeof text === "string" ? text : undefined
}

/**
 * The repository a message injected by this hook belongs to, read from its
 * details or, when a host drops details, from its heading; undefined for every
 * other message.
 */
export function injectedRepo(message: unknown): string | undefined {
  if (field(message, "customType") !== CONTEXT_MESSAGE_TYPE) return undefined
  const repo = stringField(field(message, "details"), "repo")
  if (repo !== undefined) return repo
  const heading = contentText(field(message, "content"))?.split("\n", 1)[0]
  return heading?.startsWith(HEADING_PREFIX) ? heading.slice(HEADING_PREFIX.length).trim() : undefined
}

interface RepoState {
  readonly house: boolean
  /** The injection reached the transcript or the model context (or there was nothing to inject). */
  delivered: boolean
  /** The injection was seen in the model context, so its later absence means the context dropped it. */
  observed: boolean
  /** The agent turn in which the injection was sent. */
  readonly sentTurn: number
}

export interface TrackerOptions {
  readonly projectsRoot: string
  /** The user-level AGENTS.md (`<agent dir>/AGENTS.md`), injected once per session. */
  readonly userInstructions: string | undefined
}

/**
 * Per-session state: which repositories have had their chain injected and
 * delivered. OMP runs the extension factory once per session, subagents
 * included, so one tracker per factory call is one tracker per session.
 */
export class ChainTracker {
  readonly #options: TrackerOptions
  readonly #repos = new Map<string, RepoState>()
  /** The repository whose injection accounts for the user AGENTS.md. */
  #userRepo: string | undefined
  #turn = 0

  constructor(options: TrackerOptions) {
    this.#options = options
  }

  /** Forget everything: a new or switched session holds none of the earlier injections. */
  reset(): void {
    this.#repos.clear()
    this.#userRepo = undefined
  }

  /** Counts agent turns, which bound how long an undelivered injection may hold edits back. */
  onTurnStart(): void {
    this.#turn += 1
  }

  /** Marks a repository's injection as delivered when its aside reaches the transcript. */
  onMessage(message: unknown): void {
    const repo = injectedRepo(message)
    const state = repo === undefined ? undefined : this.#repos.get(repo)
    if (state !== undefined) state.delivered = true
  }

  /**
   * Reconciles with the messages the model is about to receive. An injection
   * among them is delivered. One that was seen before and is missing now was
   * dropped (compaction, `/clear`, another branch), so the next touch of its
   * repository injects again. A resumed session recovers its earlier
   * injections the same way. An injection never seen in context is left alone,
   * so a host that folds asides into other messages cannot cause a
   * re-injection loop.
   */
  onContext(messages: unknown): void {
    const present = new Map<string, boolean>()
    for (const message of Array.isArray(messages) ? messages : []) {
      const repo = injectedRepo(message)
      if (repo === undefined) continue
      const user = field(field(message, "details"), "user") === true
      present.set(repo, present.get(repo) === true || user)
    }
    for (const [repo, state] of this.#repos) {
      if (present.has(repo)) {
        state.delivered = true
        state.observed = true
      } else if (state.observed) {
        this.#repos.delete(repo)
        if (this.#userRepo === repo) this.#userRepo = undefined
      }
    }
    for (const [repo, user] of present) {
      if (!this.#repos.has(repo)) {
        this.#repos.set(repo, { house: false, delivered: true, observed: true, sentTurn: this.#turn })
      }
      if (user && this.#userRepo === undefined) this.#userRepo = repo
    }
  }

  onToolCall(toolName: string, input: unknown, cwd: string, systemPrompt: () => string): ToolCallPlan {
    const injections: Injection[] = []
    for (const path of touchedPaths(toolName, input, cwd)) {
      const repo = findRepoRoot(path)
      if (repo === undefined || this.#repos.has(repo)) continue
      const chain = readChain(repo, this.#options.projectsRoot)
      const injection = renderChain(chain, systemPrompt(), this.#userRepo === undefined ? this.#userFile() : undefined)
      if (injection?.details.user === true) this.#userRepo = repo
      // Nothing to inject means nothing to wait for.
      this.#repos.set(repo, {
        house: chain.house !== undefined,
        delivered: injection === undefined,
        observed: false,
        sentTurn: this.#turn,
      })
      if (injection !== undefined) injections.push(injection)
    }
    const gated = new Set<string>()
    for (const target of typeScriptEdits(toolName, input, cwd)) {
      const repo = findRepoRoot(target)
      const state = repo === undefined ? undefined : this.#repos.get(repo)
      if (repo === undefined || state === undefined || !state.house || state.delivered) continue
      // Fail open: an injection that has not arrived within its turns no longer blocks.
      if (this.#turn - state.sentTurn <= GATE_TURNS) gated.add(repo)
    }
    return {
      injections,
      block:
        gated.size === 0
          ? undefined
          : `projects-tier held back this TypeScript edit. ${[...gated].join(", ")} has an ${OVERLAY_SKILL} overlay, and its instruction chain (AGENTS.md files, repository skills, and the full ${OVERLAY_SKILL} text) was just injected as a separate message. Read that message, apply it to this change, then retry the edit.`,
    }
  }

  #userFile(): ChainFile | undefined {
    const path = this.#options.userInstructions
    const text = path === undefined ? undefined : readText(path)
    return path === undefined || text === undefined ? undefined : { path, text }
  }
}
