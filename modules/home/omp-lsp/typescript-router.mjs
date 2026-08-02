import { access } from "node:fs/promises"
import { dirname, join, parse } from "node:path"

const exists = async (path) => {
  try {
    await access(path)
    return true
  } catch {
    return false
  }
}

const findWorkspace = async (start) => {
  let current = start
  const root = parse(current).root

  while (true) {
    if (await exists(join(current, "node_modules", "typescript", "package.json"))) {
      return current
    }
    if (current === root) {
      throw new Error(`No project-local TypeScript package found from ${start}`)
    }
    current = dirname(current)
  }
}

const workspace = await findWorkspace(process.cwd())
const typescriptPackage = await Bun.file(
  join(workspace, "node_modules", "typescript", "package.json"),
).json()
const major = Number.parseInt(String(typescriptPackage.version).split(".")[0] ?? "", 10)

if (!Number.isSafeInteger(major)) {
  throw new Error(`Invalid project-local TypeScript version: ${String(typescriptPackage.version)}`)
}

let command

if (major >= 7) {
  const effectLauncher = join(workspace, "node_modules", ".bin", "effect-tsgo")
  if (await exists(effectLauncher)) {
    const resolved = Bun.spawnSync({
      cmd: ["bun", effectLauncher, "get-exe-path"],
      cwd: workspace,
      stdout: "pipe",
      stderr: "pipe",
    })
    if (resolved.exitCode !== 0) {
      await Bun.stderr.write(resolved.stderr)
      throw new Error(`effect-tsgo get-exe-path exited ${resolved.exitCode}`)
    }
    const executable = resolved.stdout.toString().trim()
    if (executable.length === 0 || !(await exists(executable))) {
      throw new Error(`effect-tsgo returned an unavailable executable: ${executable}`)
    }
    command = [executable, "--lsp", "--stdio"]
  } else {
    command = [
      "bun",
      join(workspace, "node_modules", ".bin", "tsc"),
      "--lsp",
      "--stdio",
    ]
  }
} else {
  const configuredServer = process.env.OMP_TYPESCRIPT_LANGUAGE_SERVER
  if (configuredServer === undefined || configuredServer.length === 0) {
    const sharedServer = join(
      import.meta.dir,
      "node_modules",
      "typescript-language-server",
      "lib",
      "cli.mjs",
    )
    if (!(await exists(sharedServer))) {
      throw new Error("OMP_TYPESCRIPT_LANGUAGE_SERVER is not configured")
    }
    command = ["bun", sharedServer, "--stdio"]
  } else {
    command = [configuredServer, "--stdio"]
  }
}

const child = Bun.spawn({
  cmd: command,
  cwd: process.cwd(),
  env: process.env,
  stdin: "inherit",
  stdout: "inherit",
  stderr: "inherit",
})

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => child.kill(signal))
}

process.exit(await child.exited)
