/**
 * Negative controls for tests/eval/projects-tier.ts: each case breaks one rule
 * in an otherwise valid synthetic package and requires the matching
 * diagnostic, so a validator that silently accepts everything fails here.
 */
import { afterAll, describe, expect, test } from "bun:test"
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { validatePackage } from "./projects-tier.ts"

const scratch = mkdtempSync(join(tmpdir(), "projects-tier-check-"))
afterAll(() => rmSync(scratch, { recursive: true, force: true }))

const REGISTRY = `# Registry fixture

## Registry

| ID | Slug | Applies to | Requirement |
|---|---|---|---|
| FX001 | version-authority | all | Establish versions. |
| FX014 | pure-domain-core | application | Keep pure code pure. |

## Enforcement vocabulary

- \`effecttsgo/floating-effect\`
`

function skill(name: string): string {
  return `---
name: ${name}
description: Fixture skill. Use when testing the tier validator.
---

# Fixture

Look up \`node_modules/effect/AGENTS.md\` first:

\`\`\`sh
jq -r .version node_modules/effect/package.json
\`\`\`

## Rules

| Rule | Requirement | Enforcement |
|---|---|---|
| FX001 version-authority | Establish the installed version. | review-only |
| FX014 pure-domain-core | Keep total functions plain. | \`effecttsgo/floating-effect\`; test: a pure helper returns no effect |

## Done means

- Done.
`
}

const PROFILE = `---
name: effect-engineering
description: Fixture profile.
autoloadSkills:
  - effect-first
  - effect-review-exceptions
  - effect-house
---

Read \`<repo root>/.agents/skills/effect-house/SKILL.md\` before writing code.
`

let counter = 0

function write(root: string, path: string, text: string): void {
  mkdirSync(dirname(join(root, path)), { recursive: true })
  writeFileSync(join(root, path), text)
}

function fixture(): string {
  counter += 1
  const root = join(scratch, `package-${counter}`)
  write(root, "skills/effect-review-exceptions/references/rules.md", REGISTRY)
  write(root, "skills/effect-review-exceptions/SKILL.md", skill("effect-review-exceptions"))
  write(root, "skills/effect-first/SKILL.md", skill("effect-first"))
  write(root, "agents/effect-engineering.md", PROFILE)
  return root
}

function edit(root: string, path: string, change: (text: string) => string): void {
  write(root, path, change(readFileSync(join(root, path), "utf8")))
}

function expectDiagnostic(mutate: (root: string) => void, fragment: string): void {
  const root = fixture()
  mutate(root)
  const diagnostics = validatePackage(root)
  expect(diagnostics.filter((diagnostic) => diagnostic.includes(fragment))).not.toEqual([])
}

const FIRST = "skills/effect-first/SKILL.md"

describe("validatePackage", () => {
  test("accepts a valid package", () => {
    expect(validatePackage(fixture())).toEqual([])
  })

  describe("profiles", () => {
    test("rejects an autoloadSkills name that is not a tier skill", () => {
      expectDiagnostic(
        (root) => edit(root, "agents/effect-engineering.md", (text) => text.replace("  - effect-first\n", "  - effect-first\n  - effect-typo\n")),
        `names unknown skill "effect-typo"`,
      )
    })

    test("requires the effect-house overlay name and the router", () => {
      expectDiagnostic((root) => edit(root, "agents/effect-engineering.md", (text) => text.replace("  - effect-house\n", "")), `must include "effect-house"`)
      expectDiagnostic((root) => edit(root, "agents/effect-engineering.md", (text) => text.replace("  - effect-first\n", "")), `must include "effect-first"`)
    })

    test("requires the by-path overlay fallback in the body", () => {
      expectDiagnostic(
        (root) => edit(root, "agents/effect-engineering.md", (text) => text.replace(/Read .*\n$/, "Work carefully.\n")),
        "by-path overlay fallback",
      )
    })
  })

  describe("Agent Skills format", () => {
    test("rejects a name that differs from the directory", () => {
      expectDiagnostic((root) => edit(root, FIRST, (text) => text.replace("name: effect-first", "name: effect-router")), "name must equal the directory")
    })

    test("rejects a description without a Use when trigger", () => {
      expectDiagnostic((root) => edit(root, FIRST, (text) => text.replace("Use when testing", "For testing")), `lacks a "Use when" trigger`)
    })

    test("rejects a description over 1024 characters", () => {
      expectDiagnostic(
        (root) => edit(root, FIRST, (text) => text.replace("Fixture skill.", `Fixture skill ${"x".repeat(1024)}.`)),
        "exceeds 1024 characters",
      )
    })

    test("rejects frontmatter fields outside the specification", () => {
      expectDiagnostic((root) => edit(root, FIRST, (text) => text.replace("---\n\n#", "argument-hint: x\n---\n\n#")), `unexpected frontmatter field "argument-hint"`)
    })

    test("rejects a body of 500 lines or more", () => {
      expectDiagnostic((root) => edit(root, FIRST, (text) => `${text}${"line\n".repeat(500)}`), "500 or more lines")
    })

    test("rejects references nested deeper than one level", () => {
      expectDiagnostic((root) => write(root, "skills/effect-first/references/deep/more.md", "# Deep\n"), "nested more than one level")
    })

    test("rejects a relative link that does not resolve", () => {
      expectDiagnostic((root) => edit(root, FIRST, (text) => `${text}\nSee [notes](references/missing.md).\n`), `link "references/missing.md" does not resolve`)
    })
  })

  describe("tier authoring contract", () => {
    test("rejects TypeScript code blocks, labelled or not", () => {
      expectDiagnostic((root) => edit(root, FIRST, (text) => `${text}\n\`\`\`ts\nconst x = 1\n\`\`\`\n`), `code block in "ts"`)
      expectDiagnostic((root) => edit(root, FIRST, (text) => `${text}\n\`\`\`\nconst x = 1\n\`\`\`\n`), `code block in "(unlabelled)"`)
      expectDiagnostic((root) => edit(root, FIRST, (text) => `${text}\n~~~text\nconst x = 1\n~~~\n`), `code block in "text"`)
    })

    test("requires a pointer to the installed Effect guidance", () => {
      expectDiagnostic((root) => edit(root, FIRST, (text) => text.replace("`node_modules/effect/AGENTS.md`", "the docs")), "installed node_modules/effect/AGENTS.md")
    })

    test("rejects a rule row that names no enforcement", () => {
      expectDiagnostic((root) => edit(root, FIRST, (text) => text.replace("| review-only |", "| soon |")), "names no enforcement")
    })

    test("rejects a rule that is not in the FX registry", () => {
      expectDiagnostic((root) => edit(root, FIRST, (text) => text.replace("FX001 version-authority", "FX001 version-pinning")), "is not in the FX registry")
    })

    test("rejects a diagnostic that is not in the enforcement vocabulary", () => {
      expectDiagnostic((root) => edit(root, FIRST, (text) => text.replace("effecttsgo/floating-effect", "effecttsgo/made-up-rule")), "unknown diagnostic effecttsgo/made-up-rule")
    })

    test("requires a Rules section", () => {
      expectDiagnostic((root) => edit(root, FIRST, (text) => text.replace("## Rules", "## Notes")), `missing "## Rules" section`)
    })
  })
})
