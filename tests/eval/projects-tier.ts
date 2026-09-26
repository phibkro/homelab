/**
 * Validates the projects-tier OMP extension package
 * (src/users/nori/programs/projects-tier):
 *
 * - every `skills/<name>/SKILL.md` follows the Agent Skills format
 *   (https://agentskills.io/specification): allowed frontmatter fields only,
 *   `name` equal to the directory, a description of at most 1024 characters
 *   with a "Use when" trigger, a body under 500 lines, and files at most one
 *   level below the skill directory;
 * - every skill honours the tier's authoring contract: it points at the
 *   installed Effect guidance, restates no API through code blocks (only
 *   labelled shell, JSON, and YAML blocks are allowed, so a TypeScript block
 *   cannot hide behind a missing or other label), and every row of its
 *   `## Rules` table cites a registered FX rule and names its enforcement (an
 *   `effecttsgo/*` diagnostic, a `test:`, or `review-only`);
 * - every profile in `agents/` autoloads only tier skills plus the repository
 *   overlay convention name `effect-house`, and keeps the by-path overlay
 *   fallback in its body.
 *
 * Usage: bun tests/eval/projects-tier.ts <package-root>
 */
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs"
import { basename, dirname, join, relative, resolve, sep } from "node:path"

export const OVERLAY_SKILL = "effect-house"
export const ROUTER_SKILL = "effect-first"
export const REGISTRY_PATH = join("skills", "effect-review-exceptions", "references", "rules.md")
export const INSTALLED_GUIDANCE = "node_modules/effect/AGENTS.md"
export const OVERLAY_FALLBACK = ".agents/skills/effect-house/SKILL.md"

// Agent Skills frontmatter fields (https://agentskills.io/specification).
const SKILL_FIELDS: Record<string, true> = {
  name: true,
  description: true,
  license: true,
  compatibility: true,
  metadata: true,
  "allowed-tools": true,
}
const SKILL_NAME = /^[a-z0-9]+(?:-[a-z0-9]+)*$/
const USE_WHEN = /\bUse when\b/
const MAX_BODY_LINES = 500
// Code block labels a skill may use; everything else, unlabelled blocks included, is rejected.
const FENCE_LANGUAGES: Record<string, true> = { sh: true, bash: true, console: true, json: true, yaml: true }
const FENCE = /^\s*(`{3,}|~{3,})\s*([^\s`]*)/
const RULE_CELL = /^(FX\d{3}) ([a-z0-9-]+)$/
const TSGO_RULE = /effecttsgo\/[a-z0-9-]+/g
const MARKDOWN_LINK = /\[[^\]]*\]\(([^)\s]+)\)/g

interface Document {
  readonly frontmatter: Record<string, unknown>
  readonly body: string
}

interface Registry {
  readonly slugs: ReadonlyMap<string, string>
  readonly diagnostics: ReadonlySet<string>
}

function parseDocument(text: string): Document | string {
  const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(text)
  if (match === null) return "missing YAML frontmatter"
  let frontmatter: unknown
  try {
    frontmatter = Bun.YAML.parse(match[1] ?? "")
  } catch (error) {
    return `malformed YAML frontmatter: ${String(error)}`
  }
  if (typeof frontmatter !== "object" || frontmatter === null || Array.isArray(frontmatter)) {
    return "frontmatter is not a mapping"
  }
  // A YAML mapping parses to a plain object with string keys.
  return { frontmatter: frontmatter as Record<string, unknown>, body: text.slice(match[0].length) }
}

function section(body: string, heading: string): string | undefined {
  const lines = body.split("\n")
  const start = lines.findIndex((line) => line.trim() === heading)
  if (start === -1) return undefined
  const rest = lines.slice(start + 1)
  const end = rest.findIndex((line) => /^#{1,2} /.test(line))
  return (end === -1 ? rest : rest.slice(0, end)).join("\n")
}

function tableRows(markdown: string): string[][] {
  const rows = markdown
    .split("\n")
    .filter((line) => line.trimStart().startsWith("|"))
    .map((line) =>
      line
        .trim()
        .replace(/^\|/, "")
        .replace(/\|$/, "")
        .split("|")
        .map((cell) => cell.trim()),
    )
  // Drop the header row and the |---| separator.
  return rows.filter((cells, index) => index > 0 && !cells.every((cell) => /^:?-+:?$/.test(cell)))
}

export function readRegistry(root: string): Registry | string {
  const path = join(root, REGISTRY_PATH)
  if (!existsSync(path)) return `${REGISTRY_PATH}: FX registry is missing`
  const text = readFileSync(path, "utf8")
  const registrySection = section(text, "## Registry")
  const vocabularySection = section(text, "## Enforcement vocabulary")
  if (registrySection === undefined || vocabularySection === undefined) {
    return `${REGISTRY_PATH}: needs "## Registry" and "## Enforcement vocabulary" sections`
  }
  const slugs = new Map<string, string>()
  for (const [id, slug] of tableRows(registrySection)) {
    if (id !== undefined && slug !== undefined) slugs.set(id, slug)
  }
  const diagnostics = new Set(vocabularySection.match(TSGO_RULE) ?? [])
  if (slugs.size === 0 || diagnostics.size === 0) return `${REGISTRY_PATH}: registry or vocabulary is empty`
  return { slugs, diagnostics }
}

function filesUnder(directory: string): string[] {
  return readdirSync(directory, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => join(entry.parentPath, entry.name))
}

/** The info-string language of every fenced code block, `""` for an unlabelled one. */
function fenceLanguages(text: string): string[] {
  const languages: string[] = []
  let open: string | undefined
  for (const line of text.split("\n")) {
    const [, marker = "", info = ""] = FENCE.exec(line) ?? []
    if (marker === "") continue
    if (open === undefined) {
      open = marker
      languages.push(info.toLowerCase())
    } else if (info === "" && marker[0] === open[0] && marker.length >= open.length) {
      open = undefined
    }
  }
  return languages
}

function checkLinks(file: string, text: string, skillDirectory: string, report: (message: string) => void): void {
  for (const match of text.matchAll(MARKDOWN_LINK)) {
    const target = (match[1] ?? "").split("#")[0] ?? ""
    if (target === "" || target.includes("://") || target.startsWith("mailto:") || target.startsWith("/")) continue
    const resolved = resolve(dirname(file), target)
    if (!resolved.startsWith(skillDirectory + sep)) {
      report(`link "${target}" leaves the skill directory`)
    } else if (!existsSync(resolved)) {
      report(`link "${target}" does not resolve`)
    }
  }
}

function checkRules(body: string, registry: Registry, report: (message: string) => void): void {
  const rules = section(body, "## Rules")
  if (rules === undefined) {
    report(`missing "## Rules" section`)
    return
  }
  const rows = tableRows(rules)
  if (rows.length === 0) report(`"## Rules" has no rule rows`)
  for (const cells of rows) {
    const [ruleCell = "", , enforcement = ""] = cells
    if (cells.length !== 3) {
      report(`rule row "${cells.join(" | ")}" needs three cells: Rule | Requirement | Enforcement`)
      continue
    }
    const rule = RULE_CELL.exec(ruleCell)
    if (rule === null) {
      report(`rule cell "${ruleCell}" is not "FXnnn slug"`)
    } else if (registry.slugs.get(rule[1] ?? "") !== rule[2]) {
      report(`rule "${ruleCell}" is not in the FX registry`)
    }
    const diagnostics = enforcement.match(TSGO_RULE) ?? []
    for (const diagnostic of diagnostics) {
      if (!registry.diagnostics.has(diagnostic)) report(`rule "${ruleCell}" cites unknown diagnostic ${diagnostic}`)
    }
    if (diagnostics.length === 0 && !enforcement.includes("review-only") && !/\btest: \S/.test(enforcement)) {
      report(`rule "${ruleCell}" names no enforcement (effecttsgo/*, test:, or review-only)`)
    }
  }
}

function checkSkill(root: string, name: string, registry: Registry | undefined, report: (message: string) => void): void {
  const directory = join(root, "skills", name)
  const skillFile = join(directory, "SKILL.md")
  if (!existsSync(skillFile)) {
    report("SKILL.md is missing")
    return
  }
  for (const file of filesUnder(directory)) {
    const depth = relative(directory, file).split(sep).length
    if (depth > 2) report(`${relative(directory, file)} is nested more than one level below the skill`)
    if (!file.endsWith(".md")) continue
    const text = readFileSync(file, "utf8")
    for (const language of fenceLanguages(text)) {
      if (!Object.hasOwn(FENCE_LANGUAGES, language)) {
        report(`${relative(directory, file)} contains a code block in "${language || "(unlabelled)"}"; only shell, JSON, and YAML blocks are allowed`)
      }
    }
    checkLinks(file, text, directory, (message) => report(`${relative(directory, file)}: ${message}`))
  }
  const parsed = parseDocument(readFileSync(skillFile, "utf8"))
  if (typeof parsed === "string") {
    report(parsed)
    return
  }
  const { frontmatter, body } = parsed
  for (const key of Object.keys(frontmatter)) {
    if (!Object.hasOwn(SKILL_FIELDS, key)) report(`unexpected frontmatter field "${key}"`)
  }
  const skillName = frontmatter.name
  if (typeof skillName !== "string" || skillName !== name) report(`name must equal the directory "${name}"`)
  if (!SKILL_NAME.test(name) || name.length > 64) report("directory name is not a valid skill name")
  const description = frontmatter.description
  if (typeof description !== "string" || description.trim() === "") {
    report("description is missing")
  } else {
    if (description.length > 1024) report("description exceeds 1024 characters")
    if (!USE_WHEN.test(description)) report(`description lacks a "Use when" trigger`)
  }
  const metadata = frontmatter.metadata
  const metadataIsStringMap =
    typeof metadata === "object" &&
    metadata !== null &&
    !Array.isArray(metadata) &&
    Object.values(metadata).every((value) => typeof value === "string")
  if (metadata !== undefined && !metadataIsStringMap) {
    report("metadata must map strings to strings")
  }
  for (const key of ["license", "compatibility", "allowed-tools"]) {
    const value = frontmatter[key]
    if (value !== undefined && typeof value !== "string") report(`${key} must be a string`)
  }
  if (typeof frontmatter.compatibility === "string" && frontmatter.compatibility.length > 500) {
    report("compatibility exceeds 500 characters")
  }
  if (body.split("\n").length >= MAX_BODY_LINES) report(`body has ${MAX_BODY_LINES} or more lines`)
  if (!body.includes(INSTALLED_GUIDANCE)) report(`body does not point at the installed ${INSTALLED_GUIDANCE}`)
  if (registry !== undefined) checkRules(body, registry, report)
}

function checkProfile(root: string, file: string, skills: ReadonlySet<string>, report: (message: string) => void): void {
  const parsed = parseDocument(readFileSync(join(root, "agents", file), "utf8"))
  if (typeof parsed === "string") {
    report(parsed)
    return
  }
  const { frontmatter, body } = parsed
  const stem = basename(file, ".md")
  if (frontmatter.name !== stem) report(`name must equal the file name "${stem}"`)
  if (typeof frontmatter.description !== "string" || frontmatter.description.trim() === "") {
    report("description is missing")
  }
  const autoload = frontmatter.autoloadSkills
  if (!Array.isArray(autoload) || autoload.length === 0) {
    report("autoloadSkills must be a non-empty list")
  } else {
    for (const entry of autoload) {
      if (typeof entry !== "string" || (entry !== OVERLAY_SKILL && !skills.has(entry))) {
        report(`autoloadSkills names unknown skill "${String(entry)}"`)
      }
    }
    for (const required of [ROUTER_SKILL, OVERLAY_SKILL]) {
      if (!autoload.includes(required)) report(`autoloadSkills must include "${required}"`)
    }
  }
  if (!body.includes(OVERLAY_FALLBACK)) report(`body lacks the by-path overlay fallback (${OVERLAY_FALLBACK})`)
}

/** Returns one diagnostic per violation; an empty list means the package is valid. */
export function validatePackage(root: string): string[] {
  const diagnostics: string[] = []
  const skillsDirectory = join(root, "skills")
  const agentsDirectory = join(root, "agents")
  if (!existsSync(skillsDirectory) || !existsSync(agentsDirectory)) {
    return ["package needs skills/ and agents/ directories"]
  }
  const registry = readRegistry(root)
  if (typeof registry === "string") diagnostics.push(registry)
  const skills = new Set(
    readdirSync(skillsDirectory).filter((entry) => statSync(join(skillsDirectory, entry)).isDirectory()),
  )
  if (skills.size === 0) diagnostics.push("skills/ contains no skill")
  for (const skill of skills) {
    checkSkill(root, skill, typeof registry === "string" ? undefined : registry, (message) =>
      diagnostics.push(`skills/${skill}: ${message}`),
    )
  }
  const profiles = readdirSync(agentsDirectory).filter((entry) => entry.endsWith(".md"))
  if (profiles.length === 0) diagnostics.push("agents/ contains no profile")
  for (const profile of profiles) {
    checkProfile(root, profile, skills, (message) => diagnostics.push(`agents/${profile}: ${message}`))
  }
  return diagnostics
}

if (import.meta.main) {
  const root = process.argv[2]
  if (root === undefined) {
    console.error("usage: bun tests/eval/projects-tier.ts <package-root>")
    process.exit(2)
  }
  const diagnostics = validatePackage(resolve(root))
  for (const diagnostic of diagnostics) console.error(`✗ ${diagnostic}`)
  if (diagnostics.length > 0) process.exit(1)
  console.log("projects-tier: skills, rules, and profiles are valid")
}
