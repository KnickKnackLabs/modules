/** @jsxImportSource jsx-md */

import { readFileSync, readdirSync, existsSync } from "fs";
import { join, resolve } from "path";

import {
  Heading, Paragraph, CodeBlock, LineBreak, HR,
  Bold, Italic, Code, Link,
  Badge, Badges, Center, Section,
  Table, TableHead, TableRow, Cell,
  List, Item,
  Raw, HtmlLink, Sub,
} from "readme/src/components";

// ── Dynamic data ─────────────────────────────────────────────

const REPO_DIR = resolve(import.meta.dirname);
const TASK_DIR = join(REPO_DIR, ".mise/tasks");
const TEST_DIR = join(REPO_DIR, "test");

// ── Parse tasks ──────────────────────────────────────────────

interface Command {
  name: string;
  description: string;
  args: string;
}

function parseTask(filepath: string, name: string): Command {
  const src = readFileSync(filepath, "utf-8");
  const lines = src.split("\n");

  const desc =
    lines
      .find((l) => l.startsWith("#MISE description="))
      ?.match(/#MISE description="(.+)"/)?.[1] ?? "";

  const hidden = lines.some((l) => l.includes("#MISE hide=true"));

  // Build usage string from #USAGE lines
  const argParts: string[] = [];
  for (const line of lines) {
    const reqArg = line.match(/#USAGE arg "<(.+?)>"/);
    if (reqArg) { argParts.push(`<${reqArg[1]}>`); continue; }

    const optArg = line.match(/#USAGE arg "\[(.+?)\]"/);
    if (optArg) { argParts.push(`[${optArg[1]}]`); continue; }

    const flag = line.match(/#USAGE flag "(--[\w-]+)(?:\s+<[\w-]+>)?"/);
    if (flag) { argParts.push(`[${flag[1]}]`); }
  }

  return { name, description: desc, args: argParts.join(" ") };
}

function walkTasks(dir: string, prefix = ""): Command[] {
  const results: Command[] = [];
  if (!existsSync(dir)) return results;

  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".") || entry.name.startsWith("_")) continue;
    const fullPath = join(dir, entry.name);
    const taskName = prefix ? `${prefix}:${entry.name}` : entry.name;

    if (entry.isDirectory()) {
      results.push(...walkTasks(fullPath, taskName));
    } else {
      results.push(parseTask(fullPath, taskName));
    }
  }
  return results;
}

const commands = walkTasks(TASK_DIR)
  .filter((c) => c.name !== "test")
  .sort((a, b) => a.name.localeCompare(b.name));

// Count tests
const testFiles = readdirSync(TEST_DIR).filter((f) => f.endsWith(".bats"));
const testSrc = testFiles
  .map((f) => readFileSync(join(TEST_DIR, f), "utf-8"))
  .join("\n");
const testCount = [...testSrc.matchAll(/@test "/g)].length;

// ── README ─────────────────────────────────────���─────────────

const readme = (
  <>
    <Center>
      <Heading level={1}>modules</Heading>

      <Paragraph>
        <Bold>Encrypted, obfuscated git submodules — without .gitmodules.</Bold>
      </Paragraph>

      <Paragraph>
        {"Manage cross-repo references with hashed directory names and an encrypted manifest."}
        {"\n"}
        {"Outsiders see opaque gitlinks. Insiders see the full dependency graph."}
      </Paragraph>

      <Badges>
        <Badge label="lang" value="bash" color="4EAA25" logo="gnubash" logoColor="white" />
        <Badge label="tests" value={`${testCount} passing`} color="brightgreen" href="test/" />
        <Badge label="License" value="MIT" color="blue" />
      </Badges>
    </Center>

    <LineBreak />

    <Section title="Why">
      <Paragraph>
        {"Git submodules require "}
        <Code>.gitmodules</Code>
        {" — a plaintext file that exposes your dependency URLs and paths. "}
        {"Git-crypt can't encrypt it (git needs to parse it as INI config). "}
        {"So if your repo is public but your dependency graph is private, submodules leak information."}
      </Paragraph>

      <Paragraph>
        <Bold>modules</Bold>
        {" skips "}
        <Code>.gitmodules</Code>
        {" entirely. It uses plain "}
        <Code>git clone</Code>
        {" inside your repo (which git tracks as mode 160000 gitlinks — the same mechanism submodules use) "}
        {"and stores the URL/path/pin mapping in its own manifest, which "}
        <Italic>can</Italic>
        {" be encrypted."}
      </Paragraph>
    </Section>

    <Section title="Quick start">
      <CodeBlock lang="bash">{`# Install
shiv install modules

# Initialize in your repo
modules setup

# Add a dependency
modules add https://github.com/org/repo.git --name my-dep

# See what you have
modules list
modules status

# On a fresh clone: populate everything from the manifest
modules init`}</CodeBlock>
    </Section>

    <Section title="How it works">
      <CodeBlock>{[
        "  your-repo/",
        "  ├── submodules/",
        "  │   ├── .manifest      ← encrypted (name → url, path, pin)",
        "  │   ├── a8f3c12b/      ← hashed directory name",
        "  │   │   └── (cloned repo contents)",
        "  │   └── 7d2e9f01/",
        "  │       └── (another repo)",
        "  └── ...",
      ].join("\n")}</CodeBlock>

      <List>
        <Item>
          <Bold>No .gitmodules</Bold>
          {" — git tracks gitlinks (pinned commit SHAs) but has no URL metadata"}
        </Item>
        <Item>
          <Bold>Hashed paths</Bold>
          {" — directory names are SHA-1 hashes of the module name, not human-readable"}
        </Item>
        <Item>
          <Bold>Encrypted manifest</Bold>
          {" — the "}
          <Code>.manifest</Code>
          {" file maps names to URLs and can be encrypted via git-crypt"}
        </Item>
        <Item>
          <Bold>Standard git</Bold>
          {" — uses regular "}
          <Code>git clone</Code>
          {" and "}
          <Code>git add</Code>
          {" under the hood, nothing exotic"}
        </Item>
      </List>
    </Section>

    <LineBreak />

    <Section title="Commands">
      <Table>
        <TableHead>
          <Cell>Command</Cell>
          <Cell>Description</Cell>
        </TableHead>
        {commands.map((cmd) => (
          <TableRow>
            <Cell><Code>{`modules ${cmd.name}${cmd.args ? " " + cmd.args : ""}`}</Code></Cell>
            <Cell>{cmd.description}</Cell>
          </TableRow>
        ))}
      </Table>
    </Section>

    <LineBreak />

    <Section title="Testing">
      <CodeBlock lang="bash">{`git clone https://github.com/KnickKnackLabs/modules.git
cd modules && mise trust && mise install
mise run test`}</CodeBlock>

      <Paragraph>
        <Bold>{`${testCount} tests`}</Bold>
        {` across ${testFiles.length} suites, using `}
        <Link href="https://github.com/bats-core/bats-core">BATS</Link>
        {". All tests use local git repos in temp directories — no network, no external dependencies."}
      </Paragraph>

      <Paragraph>
        {"The "}
        <Code>git-mechanics</Code>
        {" suite independently verifies every git assumption the tool relies on: "}
        {"gitlinks without .gitmodules, SHA pinning, fresh clone behavior, obfuscated paths, "}
        {"and encrypted manifest coexistence."}
      </Paragraph>
    </Section>

    <Section title="Architecture">
      <CodeBlock>{[
        "modules/",
        "├── .mise/tasks/",
        "│   ├── setup       # Initialize submodules dir + manifest",
        "│   ├── add         # Clone into hashed path, record in manifest",
        "│   ├── list        # Show modules (table or --json)",
        "│   ├── init        # Populate all modules on fresh checkout",
        "│   ├── update      # Pull latest, update pinned SHA",
        "│   ├── status      # Show at-pin / changed / missing",
        "│   ├── remove      # Clean removal of clone + manifest entry",
        "│   └── test        # Run BATS test suite",
        "├── lib/",
        "│   └── common.sh   # Shared helpers (manifest ops, hashing, require checks)",
        "├── test/",
        "│   ├── test_helper.bash",
        "│   ├── git-mechanics.bats   # Git behavior verification",
        "│   ├── setup.bats",
        "│   ├── add.bats",
        "│   ├── list.bats",
        "│   ├── init.bats",
        "│   ├── update.bats",
        "│   ├── status.bats",
        "│   └── remove.bats",
        "└── mise.toml",
      ].join("\n")}</CodeBlock>
    </Section>

    <LineBreak />

    <Center>
      <HR />

      <Sub>
        {"Your dependencies, visible only to those who should see them."}
        <Raw>{"<br />"}</Raw>{"\n"}
        <Raw>{"<br />"}</Raw>{"\n"}
        {"This README was generated from "}
        <HtmlLink href="https://github.com/KnickKnackLabs/readme">README.tsx</HtmlLink>
        {"."}
      </Sub>
    </Center>
  </>
);

console.log(readme);
