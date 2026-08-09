// conformance/runner.cpp - the CPU-5 ColdFire conformance corpus runner.
//
// Check: `ctest --test-dir build --no-tests=error -R ^mcf5307_conformance_all$`
// runs every committed case and reports `0 tests failed`. The runner prints
// the failing instruction, the differing register and both values on a
// failure.
//
// The runner registers one CTest test per group, and the group is selected by
// the registered test NAME, never by a forwarded argument (CPU-5's own note
// gives the measured reason: CTest does not forward arguments after `--`, so
// each registration carries `--group <name>` in its COMMAND). Design section
// 18.2, design section 20.1, plan section 11.2.
//
// WHAT THE RUNNER IS. One executable, built from this one translation unit,
// linked against the `mcf5307` static library through the C ABI
// (`include/mcf5307.h`). It reads the committed corpus, replays each case
// against the core, and compares the resulting register state with the
// expected state. The five registered tests select the group:
//
//   `mcf5307_conformance_move`     runner --group move
//   `mcf5307_conformance_alu`      runner --group alu
//   `mcf5307_conformance_logic`    runner --group logic
//   `mcf5307_conformance_control`  runner --group control
//   `mcf5307_conformance_all`      runner            (all four groups)
//
// THE ONE REGISTER BRIDGE. The corpus contract (conformance/generate.py,
// CPU-4) requires the runner to set the `initial` registers and read back the
// `expected` registers. CPU-7 added the register file to the core and the two
// accessors `mcf5307_set_reg`/`mcf5307_get_reg` to the contract
// (`include/mcf5307.h`), and the two bodies below are that wiring. THIS
// SECTION IS THE RUNNER'S SINGLE INTEGRATION POINT FOR REGISTER ACCESS: it
// isolates the one thing the harness needs that the contract's lifecycle
// calls do not promise, so that a later change to the access touches exactly
// this section and nothing else.
//
// Clean-room note (AGENTS.md section 4.2): none of this is copied from any
// GPL or LGPL implementation. The JSON parse is a small hand-written
// recursive-descent parser for the fixed, machine-generated surface the
// project's own generator emits (see the docstring of
// `conformance/generate.py`), all of it in this one translation unit.

#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "mcf5307.h"

namespace {

// ---------------------------------------------------------------------------
// The JSON value tree and parser.
//
// The corpus is the deterministic surface `conformance/generate.py` emits:
//
//   file   = { "format":int, "group":str, "binutils":str, "cases":[case] }
//   case   = { "name":str, "mnemonic":str, "instruction":str,
//              "encoding":[str], "initial":state, "expected":state }
//   state  = { "regs":{name:int}, "mem":[ { "addr":int, "size":int,
//              "value":int } ] }
//
// The same recursive-descent parser that `conformance/parse_check.cpp`
// (CPU-4) uses, so the two agree on what the generator writes.

struct Value;
using ValuePtr = std::unique_ptr<Value>;

struct Value {
  enum class Kind { Null, Bool, Int, String, Array, Object } kind = Kind::Null;
  bool b = false;
  std::int64_t i = 0;
  std::string s;
  std::vector<ValuePtr> array;
  std::vector<std::pair<std::string, ValuePtr>> object;

  const Value* find(const std::string& key) const {
    for (const auto& kv : object) {
      if (kv.first == key) return kv.second.get();
    }
    return nullptr;
  }
};

struct ParseError {
  std::string what;
};

class Parser {
 public:
  explicit Parser(const std::string& text) : text_(text) {}

  ValuePtr parse() {
    ValuePtr root = parseValue();
    skipWs();
    if (pos_ != text_.size()) {
      fail("trailing characters after the JSON value");
    }
    return root;
  }

 private:
  const std::string& text_;
  std::size_t pos_ = 0;

  [[noreturn]] void fail(const std::string& msg) const {
    throw ParseError{msg + " (offset " + std::to_string(pos_) + ")"};
  }

  void skipWs() {
    while (pos_ < text_.size()) {
      char c = text_[pos_];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        ++pos_;
      } else {
        break;
      }
    }
  }

  char peek() {
    if (pos_ >= text_.size()) fail("unexpected end of JSON");
    return text_[pos_];
  }

  void expectLiteral(const char* lit) {
    const std::size_t n = std::strlen(lit);
    if (text_.compare(pos_, n, lit) != 0) {
      fail(std::string("expected literal '") + lit + "'");
    }
    pos_ += n;
  }

  ValuePtr parseValue() {
    skipWs();
    char c = peek();
    switch (c) {
      case '{': return parseObject();
      case '[': return parseArray();
      case '"': return parseStringValue();
      case 't': expectLiteral("true"); return mkBool(true);
      case 'f': expectLiteral("false"); return mkBool(false);
      case 'n': expectLiteral("null"); return mkNull();
      default:
        if (c == '-' || (c >= '0' && c <= '9')) return parseNumber();
        fail("unexpected character");
    }
  }

  static ValuePtr mkBool(bool b) {
    auto v = std::make_unique<Value>();
    v->kind = Value::Kind::Bool; v->b = b; return v;
  }
  static ValuePtr mkNull() {
    auto v = std::make_unique<Value>();
    v->kind = Value::Kind::Null; return v;
  }
  static ValuePtr mkString(std::string s) {
    auto v = std::make_unique<Value>();
    v->kind = Value::Kind::String; v->s = std::move(s); return v;
  }

  ValuePtr parseStringValue() {
    std::string out;
    parseStringBody(out);
    return mkString(std::move(out));
  }

  void parseStringBody(std::string& out) {
    if (peek() != '"') fail("expected '\"'");
    ++pos_;
    while (true) {
      if (pos_ >= text_.size()) fail("unterminated string");
      char c = text_[pos_];
      if (c == '"') { ++pos_; return; }
      if (c == '\\') {
        ++pos_;
        if (pos_ >= text_.size()) fail("unterminated escape");
        char e = text_[pos_++];
        switch (e) {
          case '"': out.push_back('"'); break;
          case '\\': out.push_back('\\'); break;
          case '/': out.push_back('/'); break;
          case 'b': out.push_back('\b'); break;
          case 'f': out.push_back('\f'); break;
          case 'n': out.push_back('\n'); break;
          case 'r': out.push_back('\r'); break;
          case 't': out.push_back('\t'); break;
          case 'u': fail("\\u escapes are not emitted by the generator"); break;
          default: fail("unknown escape"); break;
        }
      } else {
        out.push_back(c);
        ++pos_;
      }
    }
  }

  ValuePtr parseNumber() {
    skipWs();
    std::size_t start = pos_;
    if (peek() == '-') ++pos_;
    if (pos_ >= text_.size()) fail("incomplete number");
    while (pos_ < text_.size() && text_[pos_] >= '0' && text_[pos_] <= '9') {
      ++pos_;
    }
    if (pos_ == start || (pos_ == start + 1 && text_[start] == '-')) {
      fail("malformed number");
    }
    if (pos_ < text_.size() &&
        (text_[pos_] == '.' || text_[pos_] == 'e' || text_[pos_] == 'E')) {
      fail("floats are not a corpus register value");
    }
    const std::string tok = text_.substr(start, pos_ - start);
    auto v = std::make_unique<Value>();
    v->kind = Value::Kind::Int;
    v->i = std::stoll(tok);
    return v;
  }

  ValuePtr parseArray() {
    if (peek() != '[') fail("expected '['");
    ++pos_;
    auto v = std::make_unique<Value>();
    v->kind = Value::Kind::Array;
    skipWs();
    if (peek() == ']') { ++pos_; return v; }
    while (true) {
      v->array.push_back(parseValue());
      skipWs();
      char c = peek();
      if (c == ']') { ++pos_; return v; }
      if (c != ',') fail("expected ',' or ']' in array");
      ++pos_;
    }
  }

  ValuePtr parseObject() {
    if (peek() != '{') fail("expected '{'");
    ++pos_;
    auto v = std::make_unique<Value>();
    v->kind = Value::Kind::Object;
    skipWs();
    if (peek() == '}') { ++pos_; return v; }
    while (true) {
      skipWs();
      if (peek() != '"') fail("expected a string key");
      std::string key;
      parseStringBody(key);
      skipWs();
      if (peek() != ':') fail("expected ':' after key");
      ++pos_;
      v->object.emplace_back(std::move(key), parseValue());
      skipWs();
      char c = peek();
      if (c == '}') { ++pos_; return v; }
      if (c != ',') fail("expected ',' or '}' in object");
      ++pos_;
    }
  }
};

// ---------------------------------------------------------------------------
// The strongly-typed view the runner works over.

struct MemWrite {
  uint32_t addr;
  int size;
  uint32_t value;
};

struct Case {
  std::string name;
  std::string mnemonic;
  std::string instruction;
  std::vector<std::string> encoding;
  // Register name -> value, in the order written.
  std::vector<std::pair<std::string, uint32_t>> initialRegs;
  std::vector<std::pair<std::string, uint32_t>> expectedRegs;
  std::vector<MemWrite> initialMem;
  std::vector<MemWrite> expectedMem;
};

struct Group {
  std::string name;
  std::vector<Case> cases;
};

// ---------------------------------------------------------------------------
// Validation / marshalling of one parsed file into a Group.

struct CheckFailure {
  std::string what;
};

[[noreturn]] void failCheck(const std::string& msg) { throw CheckFailure{msg}; }

const Value& requireKind(const Value* v, Value::Kind k, const std::string& what) {
  if (v == nullptr) failCheck(what + " is missing");
  if (v->kind != k) {
    failCheck(what + " has the wrong type");
  }
  return *v;
}
const Value& requireObject(const Value* v, const std::string& w) {
  return requireKind(v, Value::Kind::Object, w);
}
const Value& requireArray(const Value* v, const std::string& w) {
  return requireKind(v, Value::Kind::Array, w);
}
const Value& requireString(const Value* v, const std::string& w) {
  return requireKind(v, Value::Kind::String, w);
}

bool isRegisterName(const std::string& name) {
  if (name.size() == 2 && (name[0] == 'd' || name[0] == 'a') &&
      name[1] >= '0' && name[1] <= '7') {
    return true;
  }
  return name == "sr" || name == "pc";
}

void collectRegs(const Value& state, const std::string& where,
                 std::vector<std::pair<std::string, uint32_t>>& out) {
  const Value* regs = state.find("regs");
  if (regs == nullptr) return;  // a state that names no register is allowed
  requireObject(regs, where + ".regs");
  for (const auto& kv : regs->object) {
    if (!isRegisterName(kv.first)) {
      failCheck(where + ".regs names '" + kv.first +
                "', which is not a register (" +
                "d0..d7, a0..a7, sr, pc)");
    }
    const Value* v = kv.second.get();
    requireKind(v, Value::Kind::Int, where + ".regs['" + kv.first + "']");
    out.emplace_back(kv.first, static_cast<uint32_t>(v->i));
  }
}

void collectMem(const Value& state, const std::string& where,
                std::vector<MemWrite>& out) {
  const Value* mem = state.find("mem");
  if (mem == nullptr) return;
  requireArray(mem, where + ".mem");
  for (std::size_t k = 0; k < mem->array.size(); ++k) {
    const std::string what = where + ".mem[" + std::to_string(k) + "]";
    const Value& item = requireObject(mem->array[k].get(), what);
    const Value* addr = item.find("addr");
    const Value* size = item.find("size");
    const Value* value = item.find("value");
    requireKind(addr, Value::Kind::Int, what + ".addr");
    requireKind(size, Value::Kind::Int, what + ".size");
    requireKind(value, Value::Kind::Int, what + ".value");
    out.push_back(
        MemWrite{static_cast<uint32_t>(addr->i), static_cast<int>(size->i),
                 static_cast<uint32_t>(value->i)});
  }
}

Group loadGroup(const std::string& path, const std::string& expectedGroup) {
  std::ifstream in(path);
  if (!in) {
    failCheck("cannot open corpus file " + path);
  }
  std::ostringstream ss;
  ss << in.rdbuf();
  const std::string text = ss.str();

  ValuePtr root;
  root = Parser(text).parse();
  const Value& r = requireObject(root.get(), path);
  const Value* fmt = r.find("format");
  requireKind(fmt, Value::Kind::Int, path + ".format");
  if (fmt->i != 1) {
    failCheck(path + ".format is " + std::to_string(fmt->i) + ", expected 1");
  }
  const Value* groupField = r.find("group");
  requireString(groupField, path + ".group");
  if (groupField->s != expectedGroup) {
    failCheck(path + ".group is '" + groupField->s + "', expected '" +
              expectedGroup + "'");
  }
  const Value& cases = requireArray(r.find("cases"), path + ".cases");

  Group g;
  g.name = expectedGroup;
  for (std::size_t k = 0; k < cases.array.size(); ++k) {
    const std::string where = path + ".cases[" + std::to_string(k) + "]";
    const Value& c = requireObject(cases.array[k].get(), where);
    Case cs;

    const Value* name = c.find("name");
    requireString(name, where + ".name");
    cs.name = name->s;
    const Value* mnemonic = c.find("mnemonic");
    requireString(mnemonic, where + ".mnemonic");
    cs.mnemonic = mnemonic->s;
    const Value* instruction = c.find("instruction");
    requireString(instruction, where + ".instruction");
    cs.instruction = instruction->s;

    const Value& enc = requireArray(c.find("encoding"), where + ".encoding");
    for (std::size_t w = 0; w < enc.array.size(); ++w) {
      const Value& word = requireString(enc.array[w].get(),
                                        where + ".encoding[" +
                                        std::to_string(w) + "]");
      cs.encoding.push_back(word.s);
    }

    const Value* initial = c.find("initial");
    if (initial == nullptr) failCheck(where + " carries no \"initial\" state");
    collectRegs(requireObject(initial, where + ".initial"),
                where + ".initial", cs.initialRegs);
    collectMem(requireObject(initial, where + ".initial"),
               where + ".initial", cs.initialMem);

    const Value* expected = c.find("expected");
    if (expected == nullptr) failCheck(where + " carries no \"expected\" state");
    collectRegs(requireObject(expected, where + ".expected"),
                where + ".expected", cs.expectedRegs);
    collectMem(requireObject(expected, where + ".expected"),
               where + ".expected", cs.expectedMem);

    g.cases.push_back(std::move(cs));
  }
  return g;
}

// ---------------------------------------------------------------------------
// The board: a byte array the core reads and writes as ColdFire memory.
//
// The encoding of each case is placed at the case's program counter, and the
// case's `initial` and `expected` `mem` writes go through the same array, so
// a memory case CPU-7..10 adds has a place without a second mechanism. A read
// of an address no case wrote answers zero and MCF5307_BUS_OK.

struct MemBoard {
  std::vector<uint8_t> bytes;

  explicit MemBoard(std::size_t n) : bytes(n, 0) {}

  void write(uint32_t addr, int size, uint32_t value) {
    if (addr + static_cast<uint32_t>(size) > bytes.size()) return;
    for (int i = 0; i < size; ++i) {
      const int shift = (size - 1 - i) * 8;
      bytes[addr + i] = static_cast<uint8_t>((value >> shift) & 0xffu);
    }
  }
  uint32_t read(uint32_t addr, int size) {
    if (addr + static_cast<uint32_t>(size) > bytes.size()) return 0;
    uint32_t v = 0;
    for (int i = 0; i < size; ++i) {
      v = (v << 8) | bytes[addr + i];
    }
    return v;
  }
};

extern "C" uint32_t boardRead(void* user, uint32_t addr, int size,
                              mcf5307_bus_status* status) {
  *status = MCF5307_BUS_OK;
  return static_cast<MemBoard*>(user)->read(addr, size);
}
extern "C" void boardWrite(void* user, uint32_t addr, int size, uint32_t value,
                           mcf5307_bus_status* status) {
  *status = MCF5307_BUS_OK;
  static_cast<MemBoard*>(user)->write(addr, size, value);
}
extern "C" void boardIack(void* user, int level, uint8_t vector) {
  (void)user; (void)level; (void)vector;
}

// ---------------------------------------------------------------------------
// THE REGISTER BRIDGE.
//
// See the file top comment. This is the runner's single integration point for
// setting the `initial` registers and reading the `expected` registers. The
// C ABI provides no register accessor and the register file is not in the
// core yet (CPU-7..10), so today every call returns false and leaves a
// diagnostic. A task that adds register access to the contract and the core
// (orifies the state block into a register profile) replaces the two bodies
// below and nothing else.

std::string registerBridgeError = "no register bridge";

// The one mapping between a corpus register name and the ABI's integer
// index: 0..7 = d0..d7, 8..15 = a0..a7, 16 = sr, 17 = pc.
int registerIndex(const std::string& name) {
  if (name.size() == 2 && (name[0] == 'd' || name[0] == 'a') &&
      name[1] >= '0' && name[1] <= '7') {
    return (name[0] == 'd' ? 0 : 8) + (name[1] - '0');
  }
  if (name == "sr") return 16;
  if (name == "pc") return 17;
  return -1;
}

bool coreWriteReg(mcf5307_ctx* ctx, const std::string& name, uint32_t value) {
  const int idx = registerIndex(name);
  if (idx < 0) {
    registerBridgeError = "no register named '" + name + "'";
    return false;
  }
  if (idx > 16) {  // pc is set through mcf5307_reset, not through the bridge
    registerBridgeError = "cannot set '" + name + "' through the bridge";
    return false;
  }
  if (mcf5307_set_reg(ctx, idx, value) == 0) {
    registerBridgeError =
        "mcf5307_set_reg refused index " + std::to_string(idx);
    return false;
  }
  return true;
}

bool coreReadReg(mcf5307_ctx* ctx, const std::string& name, uint32_t& out) {
  const int idx = registerIndex(name);
  if (idx < 0) {
    registerBridgeError = "no register named '" + name + "'";
    return false;
  }
  out = mcf5307_get_reg(ctx, idx);
  return true;
}

// ---------------------------------------------------------------------------
// Running one case.

struct CaseRun {
  bool ran = false;           // the case ran to an observable outcome
  bool ok = true;             // every expected register matched / none to check
  std::string reason;         // a precise message when !ran or !ok
  // When a register mismatched: which one, and the two values.
  std::string mismatchReg;
  uint32_t expectedValue = 0;
  uint32_t actualValue = 0;
};

CaseRun runCase(const Case& cs) {
  CaseRun out;

  // The program counter and stack pointer come from the case state when it
  // names them, and from defaults otherwise.
  const uint32_t kBaseExec = 0x10000;   // encoding base, clear of the vector
  const uint32_t kDefaultSp = 0x400000;
  uint32_t pc = kBaseExec;
  uint32_t sp = kDefaultSp;
  for (const auto& r : cs.initialRegs) {
    if (r.first == "pc") pc = r.second;
    if (r.first == "sp") sp = r.second;
  }

  // The memory board. It is reset per case so no case inherits another's
  // bytes. The board is large enough for the encoding, the vector area and
  // any memory the case names.
  MemBoard board(1u << 20);
  for (const auto& w : cs.initialMem) board.write(w.addr, w.size, w.value);

  // Place the encoding at the program counter.
  for (std::size_t i = 0; i < cs.encoding.size(); ++i) {
    uint32_t w = static_cast<uint32_t>(std::stoul(cs.encoding[i], nullptr, 16));
    board.write(pc + 2u * static_cast<uint32_t>(i), 2, w);
  }

  mcf5307_ctx* ctx = mcf5307_create(&board, boardRead, boardWrite, boardIack);
  mcf5307_reset(ctx, sp, pc);

  // Set the non-pc/sp initial registers through the bridge.
  for (const auto& r : cs.initialRegs) {
    if (r.first == "pc" || r.first == "sp") continue;
    if (!coreWriteReg(ctx, r.first, r.second)) {
      out.ran = false;
      out.ok = false;
      out.reason =
          "cannot set initial register '" + r.first + "': " +
          std::string(registerBridgeError);
      mcf5307_destroy(ctx);
      return out;
    }
  }

  // A generous budget: enough cycles to fetch the instruction and every
  // extension word and to execute it. The core returns the cycles actually
  // spent. The single exec below is the case's whole run; a case that
  // asserts no register is judged by its cycle return, so the return is kept.
  const uint32_t kBudget = 4096;
  const uint32_t cycles = mcf5307_exec(ctx, kBudget);

  // Read the expected registers and compare each. Only the registers the
  // expected state names are asserted (the corpus contract: a case that
  // affects one register does not have to state every other one).
  for (const auto& r : cs.expectedRegs) {
    uint32_t actual = 0;
    if (!coreReadReg(ctx, r.first, actual)) {
      out.ran = false;
      out.ok = false;
      out.reason =
          "cannot read expected register '" + r.first + "': " +
          std::string(registerBridgeError);
      mcf5307_destroy(ctx);
      return out;
    }
    if (actual != r.second) {
      out.ran = true;
      out.ok = false;
      out.mismatchReg = r.first;
      out.expectedValue = r.second;
      out.actualValue = actual;
      mcf5307_destroy(ctx);
      return out;
    }
  }

  // The expected memory writes. Each entry is compared against the board
  // after the exec, so a case whose effect is a store (MOVE to memory,
  // MOVEM, PEA, LINK) is verified rather than read as a register-only case.
  for (const auto& w : cs.expectedMem) {
    const uint32_t actual = board.read(w.addr, w.size);
    if (actual != w.value) {
      out.ran = true;
      out.ok = false;
      out.mismatchReg =
          "mem[" + std::to_string(w.addr) + ":" + std::to_string(w.size) + "]";
      out.expectedValue = w.value;
      out.actualValue = actual;
      mcf5307_destroy(ctx);
      return out;
    }
  }

  // No expected registers: the case passes when the instruction ran. The
  // conformance reader's only observable for "it ran" through the current
  // ABI is a non-zero cycle return from that one exec.
  if (cs.expectedRegs.empty() && cycles == 0) {
    out.ran = true;
    out.ok = false;
    out.reason = "the instruction did not execute (0 cycles returned)";
    mcf5307_destroy(ctx);
    return out;
  }

  out.ran = true;
  out.ok = true;
  mcf5307_destroy(ctx);
  return out;
}

// ---------------------------------------------------------------------------
// The driver.

void printUsage(std::ostream& os) {
  os << "usage: runner [--group move|alu|logic|control] <corpus-dir>\n"
        "  --group <name>  run only that group's cases; absent runs all four\n"
        "  <corpus-dir>    the directory holding the <group>_00.json files\n";
}

}  // namespace

int main(int argc, char** argv) {
  // The Nim runtime initialiser runs once, before the first case creates a
  // context. It is idempotent and called here rather than per case.
  mcf5307_runtime_init();

  std::string group;
  std::string corpusDir;

  for (int i = 1; i < argc; ++i) {
    const std::string a = argv[i];
    if (a == "--group") {
      if (i + 1 >= argc) {
        std::cerr << "runner: --group needs a value\n";
        printUsage(std::cerr);
        return 2;
      }
      group = argv[++i];
    } else if (a == "--help" || a == "-h") {
      printUsage(std::cout);
      return 0;
    } else if (a.rfind("--", 0) == 0) {
      std::cerr << "runner: unknown option '" << a << "'\n";
      printUsage(std::cerr);
      return 2;
    } else {
      if (!corpusDir.empty()) {
        std::cerr << "runner: more than one corpus-dir given\n";
        printUsage(std::cerr);
        return 2;
      }
      corpusDir = a;
    }
  }

  if (corpusDir.empty()) {
    std::cerr << "runner: no corpus-dir given\n";
    printUsage(std::cerr);
    return 2;
  }

  const std::vector<std::string> kAllGroups = {"move", "alu", "logic",
                                               "control"};
  std::vector<std::string> groupsToRun;
  if (!group.empty()) {
    bool found = false;
    for (const auto& g : kAllGroups) {
      if (g == group) { found = true; break; }
    }
    if (!found) {
      std::cerr << "runner: unknown group '" << group
                << "' (expected move, alu, logic or control)\n";
      return 2;
    }
    groupsToRun.push_back(group);
  } else {
    groupsToRun = kAllGroups;
  }

  bool anyLoadFault = false;
  bool anyFailure = false;
  std::size_t totalCases = 0;

  for (const std::string& g : groupsToRun) {
    const std::string path = corpusDir + "/" + g + "_00.json";
    Group groupData;
    try {
      groupData = loadGroup(path, g);
    } catch (const ParseError& e) {
      std::cerr << "runner: JSON parse error in " << path << ": " << e.what
                << "\n";
      anyLoadFault = true;
      continue;
    } catch (const CheckFailure& e) {
      std::cerr << "runner: invalid " << path << ": " << e.what << "\n";
      anyLoadFault = true;
      continue;
    } catch (const std::exception& e) {
      std::cerr << "runner: error loading " << path << ": " << e.what() << "\n";
      anyLoadFault = true;
      continue;
    }

    std::size_t groupFailures = 0;
    for (const Case& cs : groupData.cases) {
      ++totalCases;
      CaseRun run = runCase(cs);
      if (!run.ok) {
        ++groupFailures;
        anyFailure = true;
        std::cout << "FAIL  group=" << g << " case=" << cs.name
                  << " instruction=\"" << cs.instruction << "\"\n";
        if (!run.reason.empty()) {
          std::cout << "      " << run.reason << "\n";
        }
        if (!run.mismatchReg.empty()) {
          std::cout << "      " << run.mismatchReg
                    << " differs: expected=0x" << std::hex << run.expectedValue
                    << " actual=0x" << run.actualValue << std::dec << "\n";
        }
      }
    }
    std::cout << "mcf5307_conformance_" << g << ": " << groupData.cases.size()
              << " cases, " << groupFailures << " failed\n";
  }

  if (anyLoadFault) {
    std::cerr << "runner: one or more group files did not load\n";
    return 2;
  }
  if (anyFailure) {
    std::cerr << "runner: " << totalCases << " cases run, failures above\n";
    return 1;
  }
  std::cout << "runner: " << totalCases << " cases, 0 failed\n";
  return 0;
}
