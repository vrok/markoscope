// Golden-file tests for syntax highlighting, run by ./test.sh.
//
// Each tests/highlighting/NAME.LANG file is highlighted as language LANG with the app's own
// highlight.js and grammars (in JavaScriptCore, the engine behind the app's web view), and the
// resulting tokens are compared with NAME.LANG.tokens, one "scope: text" per line.
//
//   swift tests/highlighting-tests.swift <repo root> [--update]
import Foundation
import JavaScriptCore

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let update = CommandLine.arguments.contains("--update")
let casesDir = root.appendingPathComponent("tests/highlighting")
let web = root.appendingPathComponent("Resources/web")

func read(_ url: URL) -> String {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        FileHandle.standardError.write("✗ can't read \(url.path)\n".data(using: .utf8)!)
        exit(1)
    }
    return text
}

let context = JSContext()!
var scriptError: String?
context.exceptionHandler = { _, exception in scriptError = exception?.toString() }
context.evaluateScript("var console = { log() {}, warn() {}, error() {} };")
for script in ["vendor/highlight.min.js", "proto.js"] {
    context.evaluateScript(read(web.appendingPathComponent(script)), withSourceURL: web.appendingPathComponent(script))
    if let scriptError { print("✗ \(script): \(scriptError)"); exit(1) }
}

// Turns highlight.js HTML into "scope: text" lines; nested scopes are joined with " > ".
context.evaluateScript("""
function tokens(code, language) {
  const html = hljs.highlight(code, { language, ignoreIllegals: false }).value;
  const unescape = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
                         .replace(/&#x27;/g, "'").replace(/&amp;/g, '&');
  const scope = cls => cls.split(' ').map(c => c.replace(/^hljs-/, '').replace(/_+$/, '')).join('.');
  const stack = [], lines = [];
  for (const part of html.split(/(<span class="[^"]*">|<\\/span>)/)) {
    const open = part.match(/^<span class="([^"]*)">$/);
    if (open) stack.push(scope(open[1]));
    else if (part === '</span>') stack.pop();
    else if (stack.length && part.trim()) lines.push(stack.join(' > ') + ': ' + unescape(part).trim());
  }
  return lines.join('\\n') + '\\n';
}
""")

var failures = 0

// Every name a code block may use for Protocol Buffers must reach the grammar.
for alias in ["proto", "protobuf", "proto2", "proto3", "grpc"] {
    let name = context.evaluateScript("(hljs.getLanguage('\(alias)') || {}).name")?.toString()
    if name != "Protocol Buffers" {
        print("✗ ```\(alias) is not highlighted as Protocol Buffers")
        failures += 1
    }
}

let cases = (try? FileManager.default.contentsOfDirectory(at: casesDir, includingPropertiesForKeys: nil)) ?? []
for input in cases.filter({ $0.pathExtension != "tokens" }).sorted(by: { $0.path < $1.path }) {
    let language = input.pathExtension
    let expectedURL = input.appendingPathExtension("tokens")
    scriptError = nil
    let actual = context.objectForKeyedSubscript("tokens")
        .call(withArguments: [read(input), language])?.toString() ?? ""
    if let scriptError {
        print("✗ \(input.lastPathComponent): \(scriptError)")
        failures += 1
        continue
    }
    if update {
        try! actual.write(to: expectedURL, atomically: true, encoding: .utf8)
        print("↻ \(expectedURL.lastPathComponent)")
        continue
    }
    guard FileManager.default.fileExists(atPath: expectedURL.path) else {
        print("✗ \(input.lastPathComponent): no \(expectedURL.lastPathComponent) (create it with ./test.sh --update)")
        failures += 1
        continue
    }
    if actual == read(expectedURL) {
        print("✓ \(input.lastPathComponent)")
    } else {
        print("✗ \(input.lastPathComponent) highlights differently than \(expectedURL.lastPathComponent):")
        let actualURL = FileManager.default.temporaryDirectory.appendingPathComponent(expectedURL.lastPathComponent)
        try! actual.write(to: actualURL, atomically: true, encoding: .utf8)
        let diff = Process()
        diff.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        diff.arguments = ["-u", "--label", "expected", "--label", "actual", expectedURL.path, actualURL.path]
        fflush(stdout)
        try! diff.run()
        diff.waitUntilExit()
        failures += 1
    }
}

if failures > 0 {
    print("\(failures) failed")
    exit(1)
}
