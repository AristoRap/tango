#!/usr/bin/env python3
"""Differential soundness and robustness fuzzer for Tango.

The harness checks two invariants:

* ROBUSTNESS: arbitrary input must produce a successful compilation or a clean
  source diagnostic, never a compiler crash, signal, hang, or phase-contract
  break.
* SOUNDNESS: if Tango emits Go in either compilation profile, that Go must
  build with the native Go toolchain.

`dump lir` is the pre-target acceptance stage and `emit go` is the full
compilation stage. Development and release must agree on acceptance. Fuzzed
programs are compiled but never executed.

Usage: scripts/fuzz.py [seed] [n]
       scripts/fuzz.py --self-test

Defaults are seed=1 and n=400. The fixed example, idiom, and adversarial lanes
always run; n controls additional generated cases, with n/2 mutations and n/4
random-token cases. Every write stays in a private temporary directory.

"""

import argparse
import os
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys
import tempfile


REPO = Path(__file__).resolve().parent.parent
TANGO = REPO / "bin" / "tango"
EXAMPLES = REPO / "examples"

CRASH_MARKERS = (
    "Unhandled exception",
    "Invalid memory access (signal",
    "Stack overflow",
    "Nil assertion failed",
    "BUG:",
    "(Exception)",
    "(IndexError)",
    "(NilAssertionError)",
    "(KeyError)",
    "(ArgumentError)",
)

EXPR = (
    "0",
    "1",
    "-3",
    "42",
    "1_i8",
    "2_i16",
    "3_i32",
    "4_i64",
    "5_u8",
    "6_u16",
    "7_u32",
    "8_u64",
    "1.5_f64",
    "true",
    "false",
    '"tango"',
    '"n=#{n}"',
    "'x'",
    "nil",
    "n + 1",
    "n * 2",
    "n // 2",
    "n % 2",
    "1 < 2",
    "flag && n > 0",
    "[1, 2, 3]",
    '["a", "b"]',
    "[] of Int32",
    "xs.size",
    "xs.first",
    "xs.last",
    "h.size",
    'h.fetch("missing", 9)',
    '"a b c".split.size',
    '"Aé🙂".size',
)

BOOL_EXPR = (
    "true",
    "false",
    "flag",
    "n < 10",
    "n >= 0",
    "n == 3",
    "xs.size > 0",
    'h.has_key?("a")',
)

VALID_IDIOMS = (
    "def add(a : Int32, b : Int32) : Int32\n  a + b\nend\nputs add(2, 3)\n",
    "def fact(n : Int32) : Int32\n  if n <= 1\n    1\n  else\n    n * fact(n - 1)\n  end\nend\nputs fact(5)\n",
    "class Box\n  def initialize(@value : Int32)\n  end\n  def value : Int32\n    @value\n  end\nend\nputs Box.new(7).value\n",
    "def apply(x : Int32, & : Int32 -> Int32) : Int32\n  yield x\nend\nputs apply(5) { |n| n * 2 }\n",
    "xs = [1, 2, 3]\nxs[1] = 7\nxs << 9\nputs xs.size\nputs xs.last\n",
    'h = Hash(String, Int32).new\nh["b"] = 2\nh["a"] = 1\nputs h.size\nputs h.fetch("z", 9)\n',
    "def maybe(hit : Bool) : Int32?\n  hit ? 7 : nil\nend\nif value = maybe(true)\n  puts value\nend\n",
    'def choose(number : Bool) : Int32 | String\n  number ? 7 : "seven"\nend\nputs choose(true).as(Int32)\n',
    'text = "Aé🙂"\ntext.each_char { |char| puts char }\nputs text[-1]\n',
    "ch = Channel(Int32).new\nspawn { ch.send(7) }\nputs ch.receive\n",
    'begin\n  raise "boom"\nrescue ex : Exception\n  puts ex.message\nensure\n  puts "done"\nend\n',
    'puts "sum=#{1 + 2}"\nputs "a" + "b"\nputs " a b ".split.size\n',
    '"a;;b;".split(";").each { |part| puts "[#{part}]" }\n',
    'parts = "a;;b;".split(";")\nparts.each { |part| puts "[#{part}]" }\n',
    '"abc".split("").each { |part| puts "[#{part}]" }\n',
    '" a  b ".split.each { |part| puts "[#{part}]" }\n',
)

# These cases deliberately mix valid edge shapes, clean semantic rejections,
# unsupported syntax, and malformed bytes. A case becoming accepted is fine as
# long as its emitted Go builds; a rejection is fine only when it is diagnostic.
NASTIES = (
    "puts(\n",
    "if 1\n  puts 1\nend\n",
    "puts unknown_name\n",
    "break\n",
    "return 1\n",
    "x : UInt8 = -1\n",
    "x : Int8 = 100_i8 + 100_i8\nputs x\n",
    "x = 1 // 0\nputs x\n",
    'puts "a" + 1\n',
    "xs = [1, \"a\"]\nputs xs\n",
    "xs = [1, 2]\nputs xs[99]\n",
    "h = Hash(String, Int32).new\nh[1] = 2\n",
    "def f(a : Int32, a : Int32) : Int32\n  a\nend\n",
    "def f : Int32\nend\nputs f\n",
    "class A\n  def initialize(@x : Int32)\n  end\nend\nputs A.new(1) == A.new(1)\n",
    "def pick(flag : Bool) : Int32 | String | Nil\n  return nil unless flag\n  flag ? 1 : \"x\"\nend\nputs pick(true)\n",
    "def maybe_bool(flag : Bool) : Bool?\n  flag ? false : nil\nend\nif maybe_bool(true)\n  puts 1\nend\n",
    "x = " + "(" * 160 + "1" + ")" * 160 + "\nputs x\n",
    "select\nelse\n  puts 1\nend\n",
    "spawn { raise \"boom\" }\n",
    "begin\n  raise \"x\"\nrescue KeyError\n  puts 1\nend\n",
    "\x00\xff\n",
)

TOKENS = (
    "def",
    "end",
    "if",
    "else",
    "elsif",
    "unless",
    "while",
    "case",
    "when",
    "begin",
    "rescue",
    "ensure",
    "class",
    "struct",
    "spawn",
    "select",
    "puts",
    "nil",
    "true",
    "false",
    "Int32",
    "String",
    "Channel",
    "(",
    ")",
    "[",
    "]",
    "{",
    "}",
    "|",
    "=>",
    "::",
    "?",
    "!",
    '"text"',
    "1",
)

INSERT_BYTES = b"()[]{}\n ;,:?!=+-*/%&|@\"'abcdefghijklmnopqrstuvwxyz0123456789"


def is_crash(returncode, stderr):
    return (returncode is not None and returncode < 0) or any(
        marker in stderr for marker in CRASH_MARKERS
    )


def clean_diagnostic(stderr):
    return "error:" in stderr or "warning:" in stderr


def gen_program(rng, index):
    lines = [
        "n = 3",
        "flag = true",
        "xs = [1, 2, 3]",
        'h = Hash(String, Int32).new',
        'h["a"] = 1',
    ]
    for slot in range(rng.randint(1, 7)):
        lane = rng.randrange(5)
        if lane == 0:
            lines.append("puts " + rng.choice(EXPR))
        elif lane == 1:
            lines.append("value_%d_%d = %s" % (index, slot, rng.choice(EXPR)))
        elif lane == 2:
            lines.append("if %s\n  puts %s\nelse\n  puts %s\nend" % (
                rng.choice(BOOL_EXPR), rng.choice(EXPR), rng.choice(EXPR)
            ))
        elif lane == 3:
            lines.append("case n\nwhen 1\n  puts %s\nelse\n  puts %s\nend" % (
                rng.choice(EXPR), rng.choice(EXPR)
            ))
        else:
            lines.append("%d.times do |i_%d_%d|\n  puts i_%d_%d\nend" % (
                rng.randint(0, 4), index, slot, index, slot
            ))
    return "\n".join(lines) + "\n"


def mutate(source, rng):
    data = bytearray(source.encode("utf-8"))
    for _ in range(rng.randint(1, 6)):
        if not data:
            data.append(rng.choice(INSERT_BYTES))
            continue
        position = rng.randrange(len(data))
        operation = rng.random()
        if operation < 0.4:
            data[position] = rng.randrange(256)
        elif operation < 0.7:
            data.insert(position, rng.choice(INSERT_BYTES))
        else:
            del data[position]
    return data.decode("utf-8", "replace")


def random_tokens(rng):
    return " ".join(rng.choice(TOKENS) for _ in range(rng.randint(3, 45))) + "\n"


class Harness:
    def __init__(self, seed, count, timeout):
        self.seed = seed
        self.count = count
        self.timeout = timeout
        self.rng = random.Random(seed)
        self.root = Path(tempfile.mkdtemp(prefix="tango_fuzz_"))
        self.case_path = self.root / "case.tn"
        self.go_path = self.root / "main.go"
        self.output_path = self.root / "fuzz-program"
        self.go_cache = self.root / "go-cache"
        self.go_tmp = self.root / "go-tmp"
        self.go_cache.mkdir()
        self.go_tmp.mkdir()
        self.go = os.environ.get("TANGO_GO") or shutil.which("go")

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def run(self, args, source_path, timeout=None):
        try:
            process = subprocess.run(
                [str(TANGO)] + list(args) + [str(source_path)],
                capture_output=True,
                text=True,
                timeout=timeout or self.timeout,
                errors="replace",
            )
            return process.returncode, process.stdout or "", process.stderr or "", False
        except subprocess.TimeoutExpired as error:
            stdout = error.stdout.decode("utf-8", "replace") if isinstance(error.stdout, bytes) else (error.stdout or "")
            stderr = error.stderr.decode("utf-8", "replace") if isinstance(error.stderr, bytes) else (error.stderr or "")
            return None, stdout, stderr, True

    def build_go(self, source):
        self.go_path.write_text(source, encoding="utf-8")
        env = os.environ.copy()
        env.update({
            "GOCACHE": str(self.go_cache),
            "GOTMPDIR": str(self.go_tmp),
            "GOTOOLCHAIN": "local",
        })
        try:
            process = subprocess.run(
                [self.go, "build", "-o", str(self.output_path), str(self.go_path)],
                cwd=self.root,
                capture_output=True,
                text=True,
                timeout=max(30, self.timeout),
                errors="replace",
                env=env,
            )
            return process.returncode == 0, (process.stdout or "") + (process.stderr or "")
        except subprocess.TimeoutExpired:
            return False, "GO BUILD TIMEOUT"

    def classify_profile(self, source_path, release):
        profile = "release" if release else "development"
        option = ("--release",) if release else ()
        returncode, _, stderr, hung = self.run(("dump", "lir") + option, source_path)
        if hung:
            return "ROBUSTNESS", "hang in %s dump lir" % profile
        if is_crash(returncode, stderr):
            return "ROBUSTNESS", "crash in %s dump lir: %s" % (profile, first_line(stderr))
        if returncode != 0:
            if clean_diagnostic(stderr):
                return "OK_REJECTED", ""
            return "ROBUSTNESS", "non-diagnostic rejection in %s dump lir: %s" % (
                profile, first_line(stderr)
            )

        returncode, go_source, stderr, hung = self.run(("emit", "go") + option, source_path)
        if hung:
            return "ROBUSTNESS", "hang in %s emit go" % profile
        if is_crash(returncode, stderr):
            return "ROBUSTNESS", "crash in %s emit go: %s" % (profile, first_line(stderr))
        if returncode != 0:
            return "ROBUSTNESS", "%s dump lir accepted but emit go rejected: %s" % (
                profile, first_line(stderr)
            )
        if not re.search(r"(?m)^package main\s*$", go_source):
            return "ROBUSTNESS", "%s emit go succeeded without a package main" % profile

        built, error = self.build_go(go_source)
        if not built:
            rendered = re.sub(r"\S+\.go:\d+(?::\d+)?:", "", error)
            lines = [line.strip() for line in rendered.splitlines() if line.strip() and not line.startswith("#")]
            detail = lines[0][:200] if lines else "go build failed"
            return "SOUNDNESS", "%s: %s" % (profile, detail)
        return "OK_ACCEPTED", ""

    def classify(self, source_path):
        development = self.classify_profile(source_path, False)
        release = self.classify_profile(source_path, True)
        for result in (development, release):
            if result[0] in ("SOUNDNESS", "ROBUSTNESS"):
                return result
        if development[0] != release[0]:
            return "ROBUSTNESS", "profile acceptance mismatch: development=%s release=%s" % (
                development[0], release[0]
            )
        return development

    def cases(self):
        cases = []
        for path in sorted(EXAMPLES.glob("*.tn")):
            cases.append(("example/" + path.stem, path, None))
        for index, source in enumerate(VALID_IDIOMS):
            cases.append(("idiom#%d" % index, None, source))
        for index, source in enumerate(NASTIES):
            cases.append(("nasty#%d" % index, None, source))

        generated = [gen_program(self.rng, index) for index in range(self.count)]
        for index, source in enumerate(generated):
            cases.append(("gen#%d" % index, None, source))

        mutation_seeds = list(VALID_IDIOMS)
        for index in range(self.count // 2):
            cases.append(("mut#%d" % index, None, mutate(self.rng.choice(mutation_seeds), self.rng)))
        for index in range(self.count // 4):
            cases.append(("rand#%d" % index, None, random_tokens(self.rng)))
        return cases

    def execute(self):
        findings = {"SOUNDNESS": [], "ROBUSTNESS": []}
        counts = {"OK_ACCEPTED": 0, "OK_REJECTED": 0, "SOUNDNESS": 0, "ROBUSTNESS": 0}
        lane_counts = {}

        for name, existing_path, source in self.cases():
            lane = name.split("#", 1)[0].split("/", 1)[0]
            lane_counts[lane] = lane_counts.get(lane, 0) + 1
            source_path = existing_path
            if source_path is None:
                self.case_path.write_text(source, encoding="utf-8", errors="replace")
                source_path = self.case_path
            try:
                category, message = self.classify(source_path)
            except Exception as error:
                category, message = "ROBUSTNESS", "harness exception: %s" % error
            counts[category] += 1
            if category in findings and len(findings[category]) < 80:
                findings[category].append((name, message, source))

        print("seed=%d n=%d lanes=%s counts=%s" % (self.seed, self.count, lane_counts, counts))
        for category in ("SOUNDNESS", "ROBUSTNESS"):
            distinct = {}
            for name, message, source in findings[category]:
                distinct.setdefault(message[:120], (name, message, source))
            if distinct:
                print("\n#### %s: %d found, %d distinct ####" % (
                    category, counts[category], len(distinct)
                ))
                for name, message, source in distinct.values():
                    rendered = "<repository example>" if source is None else repr(source[:500])
                    print("\n--- [%s]\nMSG: %s\nSRC: %s" % (name, message, rendered))

        return 1 if counts["SOUNDNESS"] or counts["ROBUSTNESS"] else 0


def first_line(text):
    for line in text.splitlines():
        if line.strip():
            return line.strip()[:200]
    return ""


def self_test():
    assert EXPR and BOOL_EXPR and VALID_IDIOMS and NASTIES and TOKENS
    assert any('.split(";").each' in source for source in VALID_IDIOMS)
    assert clean_diagnostic("error: bad source")
    assert not clean_diagnostic("raw failure")
    assert is_crash(1, "Unhandled exception: boom")
    assert is_crash(-9, "")
    assert not is_crash(1, "error: expected expression")
    left = gen_program(random.Random(7), 0)
    right = gen_program(random.Random(7), 0)
    assert left == right
    assert mutate("puts 1\n", random.Random(3)) != "puts 1\n"
    print("fuzz harness self-test: ok")
    return 0


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Tango differential soundness/robustness fuzzer")
    parser.add_argument("seed", nargs="?", type=int, default=1)
    parser.add_argument("n", nargs="?", type=int, default=400)
    parser.add_argument("--timeout", type=int, default=8, help="per-compiler-stage timeout in seconds")
    parser.add_argument("--self-test", action="store_true", help="test the harness without invoking Tango or Go")
    args = parser.parse_args(argv)
    if args.n < 0:
        parser.error("n must be non-negative")
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    return args


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    if args.self_test:
        return self_test()
    if not TANGO.exists():
        print("fuzz: %s not found; run `make build` first" % TANGO, file=sys.stderr)
        return 2

    harness = Harness(args.seed, args.n, args.timeout)
    if not harness.go:
        harness.close()
        print("fuzz: Go toolchain not found; run `bin/tango doctor`" , file=sys.stderr)
        return 2
    try:
        return harness.execute()
    finally:
        harness.close()


if __name__ == "__main__":
    sys.exit(main())
