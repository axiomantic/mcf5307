// conformance/parse_check.cpp - the CPU-4 conformance corpus parse check.
//
// The Check: line for CPU-4 is split by platform. On macOS arm64 and Windows
// x86-64 there is no m68k cross assembler, so this is the check: it loads
// the committed corpus and asserts the corpus parses and is complete.
//
//   the corpus has every group CPU-7 to CPU-10 name, and
//   every case carries an instruction, an initial state and an expected
//   final state.
//
// This is a pure-C++ program. It links nothing but the C and C++ runtimes,
// it needs no Nim, and it needs no cross assembler. It is the registered
// test t0_corpus_parses.
//
// The JSON it must understand is exactly the deterministic surface the
// conformance generator (conformance/generate.py) emits, as documented in
// that file's docstring:
//
//   file   = { "format":int, "group":str, "binutils":str, "cases":[case] }
//   case   = { "name":str, "mnemonic":str, "instruction":str,
//              "encoding":[str], "initial":state, "expected":state }
//   state  = { "regs":{str:int}, "mem":[ { "addr":int, "size":int,
//              "value":int } ] }
//
// The whole parser is written here rather than importing a JSON library so
// t0_corpus_parses has no dependency beyond the toolchain that already
// builds every other test in this tree. It is a recursive-descent parser
// over the JSON grammar subset the generator emits, and it rejects anything
// outside that subset loudly enough to name the file, the case and the
// field.
//
// Clean-room note (AGENTS.md section 4.2): none of this is copied from any
// GPL or LGPL JSON implementation. It is a small hand-written parser for a
// fixed-format, machine-generated document, and all the code lives in this
// one translation unit.

#include <cstdint>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace {

// ---------------------------------------------------------------------------
// The JSON value tree.

struct Value;
using ValuePtr = std::unique_ptr<Value>;

struct Value {
  enum class Kind { Null, Bool, Int, String, Array, Object } kind = Kind::Null;
  bool b = false;
  std::int64_t i = 0;
  std::string s;
  std::vector<ValuePtr> array;
  // Object pairs kept in insertion order so a failure can name the key in
  // the order it was written. Lookups are linear because these objects hold
  // at most a handful of keys.
  std::vector<std::pair<std::string, ValuePtr>> object;

  const Value* find(const std::string& key) const {
    for (const auto& kv : object) {
      if (kv.first == key) return kv.second.get();
    }
    return nullptr;
  }
};

// ---------------------------------------------------------------------------
// The parser.

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
    if (text_.compare(pos_, std::string(lit).size(), lit) != 0) {
      fail(std::string("expected literal '") + lit + "'");
    }
    pos_ += std::string(lit).size();
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
    std::string tok = text_.substr(start, pos_ - start);
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
// Validation helpers.

const char* kindName(Value::Kind k) {
  switch (k) {
    case Value::Kind::Null: return "null";
    case Value::Kind::Bool: return "bool";
    case Value::Kind::Int: return "int";
    case Value::Kind::String: return "string";
    case Value::Kind::Array: return "array";
    case Value::Kind::Object: return "object";
  }
  return "unknown";
}

struct CheckFailure {
  std::string what;
};

[[noreturn]] void failCheck(const std::string& msg) {
  throw CheckFailure{msg};
}

const Value& requireKind(const Value* v, Value::Kind k, const std::string& what) {
  if (v == nullptr) failCheck(what + " is missing");
  if (v->kind != k) {
    failCheck(what + " has type " + kindName(v->kind) + ", expected " +
              kindName(k));
  }
  return *v;
}

const Value& requireObject(const Value* v, const std::string& what) {
  return requireKind(v, Value::Kind::Object, what);
}
const Value& requireArray(const Value* v, const std::string& what) {
  return requireKind(v, Value::Kind::Array, what);
}
const Value& requireString(const Value* v, const std::string& what) {
  return requireKind(v, Value::Kind::String, what);
}
const Value& requireInt(const Value* v, const std::string& what) {
  return requireKind(v, Value::Kind::Int, what);
}

bool isRegisterName(const std::string& name) {
  if (name.size() == 2 && (name[0] == 'd' || name[0] == 'a') &&
      name[1] >= '0' && name[1] <= '7') {
    return true;
  }
  return name == "sr" || name == "pc";
}

void validateRegs(const Value& regs, const std::string& where) {
  const std::string what = where + ".regs";
  for (const auto& kv : regs.object) {
    if (!isRegisterName(kv.first)) {
      failCheck(what + " names '" + kv.first + "', which is not a register this "
                "corpus addresses (d0..d7, a0..a7, sr, pc)");
    }
    requireInt(kv.second.get(), what + "['" + kv.first + "']");
  }
}

void validateState(const Value& state, const std::string& where) {
  requireObject(&state, where);
  const Value* regs = state.find("regs");
  if (regs == nullptr) {
    failCheck(where + " carries no \"regs\" object: a state must name its "
              "registers");
  }
  requireObject(regs, where + ".regs");
  validateRegs(*regs, where);
  if (const Value* mem = state.find("mem")) {
    requireArray(mem, where + ".mem");
  }
}

void validateEncoding(const Value& enc, const std::string& where) {
  requireArray(&enc, where + ".encoding");
  if (enc.array.empty()) {
    failCheck(where + ".encoding is empty: an encoding of no words means the "
              "instruction was never assembled");
  }
  for (std::size_t k = 0; k < enc.array.size(); ++k) {
    const Value& w = requireString(
        enc.array[k].get(), where + ".encoding[" + std::to_string(k) + "]");
    if (w.s.size() != 4) {
      failCheck(where + ".encoding[" + std::to_string(k) + "] is '" + w.s +
                "', not a 4-hex-digit word");
    }
    for (char c : w.s) {
      bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
      if (!ok) {
        failCheck(where + ".encoding[" + std::to_string(k) + "] is '" + w.s +
                  "', not lower-case hex");
      }
    }
  }
}

void validateCase(const Value& c, const std::string& where) {
  requireObject(&c, where);

  const Value* name = c.find("name");
  requireString(name, where + ".name");
  if (name->s.empty()) failCheck(where + ".name is empty");

  const Value* mnemonic = c.find("mnemonic");
  requireString(mnemonic, where + ".mnemonic");
  if (mnemonic->s.empty()) failCheck(where + ".mnemonic is empty");

  const Value* instruction = c.find("instruction");
  requireString(instruction, where + ".instruction");
  if (instruction->s.empty()) {
    failCheck(where + ".instruction is empty: every case must carry an "
              "instruction");
  }

  const Value* encoding = c.find("encoding");
  validateEncoding(*encoding, where);

  const Value* initial = c.find("initial");
  if (initial == nullptr) failCheck(where + " carries no \"initial\" state");
  validateState(*initial, where + ".initial");

  const Value* expected = c.find("expected");
  if (expected == nullptr) failCheck(where + " carries no \"expected\" state");
  validateState(*expected, where + ".expected");
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: t0_corpus_parses <corpus-dir>\n";
    return 2;
  }
  const std::string corpus_dir = argv[1];
  const std::string suffix = "_00.json";

  // The four groups CPU-7 to CPU-10 name. The parse must find every one.
  const std::vector<std::string> kRequiredGroups = {
      "move", "alu", "logic", "control"};

  std::size_t total_cases = 0;
  std::vector<std::string> failures;

  for (const std::string& group : kRequiredGroups) {
    const std::string path = corpus_dir + "/" + group + suffix;
    std::cout << "parsing " << path << "\n";

    std::ifstream in(path);
    if (!in) {
      std::cerr << "cannot open corpus file " << path << "\n";
      failures.push_back("missing group file " + group + suffix);
      continue;
    }
    std::ostringstream ss;
    ss << in.rdbuf();
    const std::string text = ss.str();

    ValuePtr root;
    try {
      root = Parser(text).parse();
      if (root == nullptr || root->kind != Value::Kind::Object) {
        failCheck(path + " is not a JSON object");
      }
      // The file is its group's, and the "group" field must agree.
      const Value* fmt = root->find("format");
      requireInt(fmt, path + ".format");
      if (fmt->i != 1) {
        failCheck(path + ".format is " + std::to_string(fmt->i) +
                  ", expected 1");
      }
      const Value* group_field = root->find("group");
      requireString(group_field, path + ".group");
      if (group_field->s != group) {
        failCheck(path + ".group is '" + group_field->s + "', expected '" +
                  group + "'");
      }
      const Value& cases = requireArray(root->find("cases"),
                                     path + ".cases");
      if (cases.array.empty()) {
        failCheck(path + " has no cases: every group must be present with at "
                  "least one case");
      }
      for (std::size_t k = 0; k < cases.array.size(); ++k) {
        validateCase(*cases.array[k],
                     path + ".cases[" + std::to_string(k) + "]");
      }
      total_cases += cases.array.size();
      std::cout << "  " << cases.array.size() << " cases\n";
    } catch (const ParseError& e) {
      std::cerr << "JSON parse error in " << path << ": " << e.what << "\n";
      failures.push_back("JSON parse error in " + group + suffix);
    } catch (const CheckFailure& e) {
      std::cerr << "invalid " << path << ": " << e.what << "\n";
      failures.push_back("check failure in " + group + suffix);
    }
  }

  if (!failures.empty()) {
    std::cerr << "t0_corpus_parses: " << failures.size()
              << " problem(s) across 4 required groups\n";
    return 1;
  }
  std::cout << "t0_corpus_parses: 4 groups, " << total_cases
            << " cases passed\n";
  return 0;
}
