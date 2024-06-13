// Compile QuakeC bytecode.
//
// reference:
// https://github.com/vkazanov/tree-sitter-quakec/blob/main/grammar.js
//
// cmd: clear && zig build-exe -freference-trace qvm.zig && ./qvm ../data/pak/progs.dat
// test: clear && zig test qcc.zig
const std = @import("std");
const dat = @import("dat");

const ParseError = error {
  EmptySource,
  UnexpectedInput,
  NoSpaceLeft,
  NotAVectorMissingLeadingQuote,
  NotAVectorMissingClosingQuote,
  NotAVector,
  NotAType,
};

fn makeError(errcode: ParseError, location: ?Location, err: *GenericError, comptime format: []const u8,
  args: anytype) ParseError {
  if (location) |loc| {
    _ = try std.fmt.bufPrint(&err.message, "error:{}:{}: " ++ format,
      .{ loc.row, loc.column } ++ args);
  } else {
    _ = try std.fmt.bufPrint(&err.message, "error: " ++ format, args);
  }
  return errcode;
}

pub const Token = struct {
  tag: Tag,
  start: usize,
  end: usize,

  pub const Tag = enum {
    eof,
    // new_line,

    dot,
    comma,
    semicolon,
    l_paren,
    r_paren,
    l_bracket,
    r_bracket,
    l_brace,
    r_brace,
    equal,
    double_equal,
    not_equal,
    not,
    plus,
    minus,
    elipsis,
    comment,
    quote,
    double_quote,
    slash,
    and_,
    or_,
    ampersand,
    pipe,
    true,
    false,

    identifier,
    type,
    vector_literal,
    string_literal,
    float_literal,
    builtin_literal,

    kw_if,
    kw_else,
    kw_while,
    kw_do,
    kw_local,
    kw_return,
  };
};

pub const Location = struct {
  column: u32,
  row: u32,
};

pub const GenericError = struct {
  message: [255:0]u8 = [_:0]u8{ 0 } ** 255,
  location: Location = .{ .column = 0, .row = 0 },
};

pub fn getLocation(buffer: []const u8, index: usize) Location {
  var i: usize = 0;
  var location = Location{ .column = 0, .row = 0 };
  while (i < index) : (i += 1) {
    location.column += 1;
    if (buffer[i] == '\n') {
      location.column = 0;
      location.row += 1;
    }
  }
  return location;
}

pub const Tokenizer = struct {
  const Self = @This();

  buffer: [:0]const u8,
  index: usize,

  const State = enum {
    start,
    identifier,
    builtin_literal,
    float_literal,
    string_literal,
    vector_literal,
    comment,
  };

  pub fn init(buffer: [:0]const u8) Self {
    return Self {
      .buffer = buffer,
      .index = 0,
    };
  }

  pub fn next(self: *Self, err: *GenericError) !Token {
    const token = try self.peek(err);
    self.index = token.end + 1;
    return token;
  }

  pub fn peek(self: *Self, err: *GenericError) !Token {
    var state = State.start;
    var result = Token {
      .tag = .eof,
      .start = self.index,
      .end = self.index,
    };

    if (self.index > self.buffer.len) {
      result.start -= 1;
      result.end -= 1;
      return result;
    }

    var index = self.index;
    while (index < self.buffer.len) {
      switch (state) {
        .start => switch (self.buffer[index]) {
          ' ', '\t', '\n', '\r' => index += 1, // ignore whitespace
          '(' => {
            result.tag = .l_paren;
            result.start = index;
            result.end = index;
            return result;
          },
          ')' => {
            result.tag = .r_paren;
            result.start = index;
            result.end = index;
            return result;
          },
          '[' => {
            result.tag = .l_bracket;
            result.start = index;
            result.end = index;
            return result;
          },
          ']' => {
            result.tag = .r_bracket;
            result.start = index;
            result.end = index;
            return result;
          },
          '{' => {
            result.tag = .l_brace;
            result.start = index;
            result.end = index;
            return result;
          },
          '}' => {
            result.tag = .r_brace;
            result.start = index;
            result.end = index;
            return result;
          },
          '.' => {
            result.start = index;
            if (std.mem.eql(u8, self.buffer[index..index + 3], "...")) {
              result.tag = .elipsis;
              result.end = index + 2;
              return result;
            } else if (index + 1 < self.buffer.len and
              std.ascii.isDigit(self.buffer[index + 1])) {
              state = .float_literal;
            } else {
              result.tag = .dot;
              result.end = index;
              return result;
            }
          },
          '+' => {
            result.tag = .plus;
            result.start = index;
            result.end = index;
            return result;
          },
          '-' => {
            result.tag = .minus;
            result.start = index;
            result.end = index;
            return result;
          },
          ',' => {
            result.tag = .comma;
            result.start = index;
            result.end = index;
            return result;
          },
          ';' => {
            result.tag = .semicolon;
            result.start = index;
            result.end = index;
            return result;
          },
          '=' => {
            result.start = index;
            if (index + 1 < self.buffer.len and self.buffer[index + 1] == '=') {
              result.tag = .double_equal;
              result.end = index + 1;
            } else {
              result.tag = .equal;
              result.end = index;
            }
            return result;
          },
          '&' => {
            result.start = index;
            if (index + 1 < self.buffer.len and self.buffer[index + 1] == '&') {
              result.tag = .and_;
              result.end = index + 1;
            } else {
              result.tag = .ampersand;
              result.end = index;
            }
            return result;
          },
          '|' => {
            result.start = index;
            if (index + 1 < self.buffer.len and self.buffer[index + 1] == '|') {
              result.tag = .or_;
              result.end = index + 1;
            } else {
              result.tag = .pipe;
              result.end = index;
            }
            return result;
          },
          '!' => {
            result.start = index;
            if (index + 1 < self.buffer.len and self.buffer[index + 1] == '=') {
              result.tag = .not_equal;
              result.end = index + 1;
            } else {
              result.tag = .not;
              result.end = index;
            }
            return result;
          },
          '"' => {
            state = .string_literal;
            result.start = index;
            index += 1;
          },
          '\'' => {
            state = .vector_literal;
            result.start = index;
            index += 1;
          },
          '/' => {
            if (index + 1 < self.buffer.len and self.buffer[index + 1] == '/') {
              state = .comment;
              result.start = index;
              index += 1;
            } else {
              result.tag = .slash;
              result.start = index;
              result.end = index;
              return result;
            }
          },
          '#' => {
            state = .builtin_literal;
            result.start = index;
            index += 1;
          },
          'a'...'z', 'A'...'Z', '_' => {
            const i = index;
            if (self.buffer[i] == 'f' and i + "false".len < self.buffer.len and
              std.mem.eql(u8, self.buffer[i..i + "false".len], "false")) {
              result.tag = .false;
              result.start = index;
              result.end = index + "false".len - 1;
              return result;
            } else if (self.buffer[i] == 't' and i + "true".len < self.buffer.len and
              std.mem.eql(u8, self.buffer[i..i + "true".len], "true")) {
              result.tag = .true;
              result.start = index;
              result.end = index + "true".len - 1;
              return result;
            } else {
              state = .identifier;
              result.start = index;
            }
          },
          '0'...'9' => {
            state = .float_literal;
            result.start = index;
          },
          else => |c| {
            _ = try std.fmt.bufPrintZ(&err.message, "unexpected character: {c}", .{ c });
            err.location = getLocation(self.buffer, index);
            return error.UnexpectedCharacter;
          },
        },
        .identifier => switch (self.buffer[index]) {
          'a'...'z', 'A'...'Z', '_' => {
            result.tag = .identifier;
            result.end = index;
            index += 1;
          },
          else => {
            const KeywordEnum = enum {
              @"void", @"float", @"string", @"vector", @"if", @"else", @"while", @"do", @"local", @"return", @"0unknown",
            };
            switch (std.meta.stringToEnum(KeywordEnum, self.buffer[result.start..result.end + 1]) orelse .@"0unknown") {
              .@"void", .@"float", .@"string", .@"vector" => result.tag = .type,
              .@"if" => result.tag = .kw_if,
              .@"else" => result.tag = .kw_else,
              .@"while" => result.tag = .kw_while,
              .@"do" => result.tag = .kw_do,
              .@"local" => result.tag = .kw_local,
              .@"return" => result.tag = .kw_return,
              .@"0unknown" => result.tag = .identifier,
            }
            return result;
          }
        },
        .builtin_literal => switch (self.buffer[index]) {
          '0'...'9' => {
            result.tag = .builtin_literal;
            result.end = index;
            index += 1;
          },
          else => return result,
        },
        .float_literal => switch (self.buffer[index]) {
          '0'...'9', '.' => {
            result.tag = .float_literal;
            result.end = index;
            index += 1;
          },
          else => return result,
        },
        .string_literal => switch (self.buffer[index]) {
          '"' => {
            result.tag = .string_literal;
            result.end = index;
            return result;
          },
          else => {
            result.tag = .string_literal;
            result.end = index;
            index += 1;
          }
        },
        .vector_literal => switch (self.buffer[index]) {
          '\'' => {
            result.tag = .vector_literal;
            result.end = index;
            return result;
          },
          '0'...'9', '+', '-', '.', ' ', '\t', '\n', '\r' => {
            result.tag = .vector_literal;
            result.end = index;
            index += 1;
          },
          else => |c| {
            _ = try std.fmt.bufPrintZ(&err.message, "unexpected character in vector literal: {c}", .{ c });
            err.location = getLocation(self.buffer, index);
            return error.UnexpectedCharacter;
          },
        },
        .comment => switch (self.buffer[index]) {
          '\n' => {
            result.tag = .comment;
            result.end = index;
            return result;
          },
          else => index += 1,
        },
      }
    }

    return result;
  }

};

const Ast = struct {
  const QType = enum {
    Void,
    Float,
    Vector,
    String,

    const Self = @This();
    pub fn prettyPrint(self: Self, string: []u8) !usize {
      switch (self) {
        .Void => return (try std.fmt.bufPrint(string, "void", .{})).len,
        .Float => return (try std.fmt.bufPrint(string, "float", .{})).len,
        .Vector => return (try std.fmt.bufPrint(string, "vector", .{})).len,
        .String => return (try std.fmt.bufPrint(string, "string", .{})).len,
      }
    }

    pub fn fromName(name: []const u8) !Self {
      if (std.mem.eql(u8, name, "void")) {
        return QType.Void;
      }
      if (std.mem.eql(u8, name, "float")) {
        return QType.Float;
      }
      if (std.mem.eql(u8, name, "vector")) {
        return QType.Vector;
      }
      if (std.mem.eql(u8, name, "string")) {
        return QType.String;
      }
      return error.NotAType;
    }
  };

  const QValue = union(QType) {
    Void: void,
    Float: f32,
    Vector: @Vector(3, f32),
    String: []const u8,

    const Self = @This();
    pub fn prettyPrint(self: Self, string: []u8) !usize {
      switch (self) {
        .Void => return (try std.fmt.bufPrint(string, "void", .{})).len,
        .Float => |f| return (try std.fmt.bufPrint(string, "{d}", .{ f })).len,
        .Vector => |v| {
          return (try std.fmt.bufPrint(string, "'{d} {d} {d}'", .{ v[0], v[1], v[2] })).len;
        },
        .String => |s| return (try std.fmt.bufPrint(string, "{s}", .{ s })).len,
      }
    }
  };

  const Program = struct {
    declarations: []const Node,
  };

  const VarDecl = struct {
    type: QType,
    name: []const u8,
    value: ?Expression,
  };

  const ParamType = enum {
    elipsis,
    declaration,
  };

  const ParamDecl = struct {
    param: union(ParamType) {
      elipsis: void,
      declaration: struct {
        type: QType,
        name: []const u8,
      },
    },

    const Self = @This();
    pub fn prettyPrint(self: Self, string: []u8) !usize {
      switch (self.param) {
        .elipsis => {
          return (try std.fmt.bufPrint(string, "...", .{})).len;
        },
        .declaration => |param| {
          const written = try param.type.prettyPrint(string);
          return written + (try std.fmt.bufPrint(string[written..], " {s}", .{ param.name })).len;
        },
      }
    }
  };

  const IfStatement = struct {
    condition: Expression,
    statement: []const Statement,
    else_statement: []const Statement,
  };

  const WhileStatement = struct {
    condition: Expression,
    statement: []const Statement,
  };

  const StatementType = enum {
    var_decl,
    return_statement,
    if_statement,
    while_statement,
    do_while_statement,
  };

  const Statement = union {
    var_decl: VarDecl,
    return_statement: Expression,
    if_statement: IfStatement,
    while_statement: WhileStatement,
    do_while_statement: WhileStatement,
    expression: Expression,

    const Self = @This();
    pub fn prettyPrint(self: Self, string: []u8) !usize {
      _ = self;
      _ = string;
      return 0;
    }
  };

  const BodyType = enum {
    statement_list,
    builtin_immediate,
  };

  const Body = union(BodyType) {
    statement_list: []const Statement,
    builtin_immediate: u16,

    const Self = @This();
    pub fn prettyPrint(self: Self, string: []u8) !usize {
      switch (self) {
        .statement_list => |list| {
          if (list.len == 1) {
            return try list[0].prettyPrint(string);
          } else {
            var written: usize = 0;
            written += (try std.fmt.bufPrint(string[written..], "{{", .{})).len;
            if (list.len > 0) {
              written += (try std.fmt.bufPrint(string[written..], "\n", .{})).len;
            }
            for (list) |statement| {
              written += try statement.prettyPrint(string[written..]);
              written += (try std.fmt.bufPrint(string[written..], "\n", .{})).len;
            }
            written += (try std.fmt.bufPrint(string[written..], "}}", .{})).len;
            return written;
          }
        },
        .builtin_immediate => |index| {
          return (try std.fmt.bufPrint(string, "#{}", .{ index })).len;
        },
      }
    }
  };

  const FnDecl = struct {
    return_type: QType,
    name: []const u8,
    parameter_list: []const ParamDecl,
    body: ?Body,
    // Storage for the parameter list
    _storage: [32]ParamDecl = undefined,
  };

  const FieldDecl = struct {
    type: QType,
    name: []const u8,
  };

  const BuiltinDecl = struct {
    name: []const u8,
    return_type: QType,
    parameter_list: []const ParamDecl,
    index: usize,
    // Storage for the parameter list
    _storage: [32]ParamDecl = undefined,
  };

  const FloatLiteral = struct {
    value: f32,
  };

  const ExpressionType = enum {
    float_literal,
    string_literal,
    vector_literal,
  };

  const StringLiteral = struct {
    value: []const u8,
  };

  const VectorLiteral = struct {
    value: @Vector(3, f32),

    pub fn fromString(str: []const u8) !VectorLiteral {
      if (str[0] != '\'') return error.NotAVectorMissingLeadingQuote;
      if (str[str.len - 1] != '\'') return error.NotAVectorMissingClosingQuote;
      var it = std.mem.splitScalar(u8, str[1..str.len - 1], ' ');
      var part = it.next();
      const x = if (part) |p|
        std.fmt.parseFloat(f32, p) catch return error.NotAVector else return error.NotAVector;
      part = it.next();
      const y = if (part) |p|
        std.fmt.parseFloat(f32, p) catch return error.NotAVector else return error.NotAVector;
      part = it.next();
      const z = if (part) |p|
        std.fmt.parseFloat(f32, p) catch return error.NotAVector else return error.NotAVector;
      return VectorLiteral{
        .value = @Vector(3, f32){ x, y, z },
      };
    }
  };

  const Expression = union(ExpressionType) {
    float_literal: FloatLiteral,
    string_literal: StringLiteral,
    vector_literal: VectorLiteral,

    pub fn prettyPrint(self: @This(), string: []u8) !usize {
      var written: usize = 0;
      switch (self) {
        .float_literal => |f| {
          written += (try std.fmt.bufPrint(string[written..], "{d}", .{ f.value })).len;
        },
        .string_literal => |s| {
          written += (try std.fmt.bufPrint(string[written..], "{s}", .{ s.value })).len;
        },
        .vector_literal => |s| {
          written += (try std.fmt.bufPrint(string[written..], "'{d} {d} {d}'", .{
            s.value[0], s.value[1], s.value[2],
          })).len;
        },
      }
      return written;
    }
  };

  const NodeType = enum {
    program,
    var_decl,
    fn_decl,
    field_decl,
    builtin_decl,
    expression,
  };

  const Node = union(NodeType) {
    program: Program,
    var_decl: VarDecl,
    fn_decl: FnDecl,
    field_decl: FieldDecl,
    builtin_decl: BuiltinDecl,
    expression: Expression,

    pub fn prettyPrint(self: @This(), string: []u8) !usize {
      var written: usize = 0;
      switch (self) {
        .var_decl => |d| {
          written += try d.type.prettyPrint(string[written..]);
          written += (try std.fmt.bufPrint(string[written..], " {s}", .{ d.name })).len;
          if (d.value) |value| {
            written += (try std.fmt.bufPrint(string[written..], " = ", .{})).len;
            written += try value.prettyPrint(string[written..]);
          }
          written += (try std.fmt.bufPrint(string[written..], ";", .{})).len;
        },
        .fn_decl => |d| {
          written += try d.return_type.prettyPrint(string[written..]);
          written += (try std.fmt.bufPrint(string[written..], " (", .{})).len;
          for (d.parameter_list, 0..) |param, i| {
            written += try param.prettyPrint(string[written..]);
            if (i < d.parameter_list.len - 1) {
              written += (try std.fmt.bufPrint(string[written..], ", ", .{})).len;
            }
          }
          written += (try std.fmt.bufPrint(string[written..], ") {s}", .{ d.name })).len;
          if (d.body) |body| {
            written += (try std.fmt.bufPrint(string[written..], " = ", .{})).len;
            written += try body.prettyPrint(string[written..]);
          } else {
            written += (try std.fmt.bufPrint(string[written..], ";", .{})).len;
          }
        },
        .field_decl => |d| {
          written += (try std.fmt.bufPrint(string[written..], ".", .{})).len;
          written += try d.type.prettyPrint(string[written..]);
          written += (try std.fmt.bufPrint(string[written..], " {s}", .{ d.name })).len;
          written += (try std.fmt.bufPrint(string[written..], ";", .{})).len;
        },
        .builtin_decl => |d| {
          written += try d.return_type.prettyPrint(string[written..]);
          written += (try std.fmt.bufPrint(string[written..], " (", .{})).len;
          for (d.parameter_list, 0..) |param, i| {
            written += try param.prettyPrint(string[written..]);
            if (i < d.parameter_list.len - 1) {
              written += (try std.fmt.bufPrint(string[written..], ", ", .{})).len;
            }
          }
          written += (try std.fmt.bufPrint(string[written..], ") {s} = #{};", .{ d.name, d.index })).len;
        },
        .expression => |expression| {
          written += try expression.prettyPrint(string[written..]);
        },
        .program => |p| {
          for (p.declarations) |declaration| {
            written += try declaration.prettyPrint(string[written..]);
          }
        },
        // .scope => |s| {
        //   written += (try std.fmt.bufPrint(string[written..], "{{\n", .{})).len;
        //   for (s.instructions) |param| {
        //     // TODO: indentation here
        //     written += try param.prettyPrint(string[written..]);
        //     written += (try std.fmt.bufPrint(string[written..], "\n", .{})).len;
        //   }
        //   written += (try std.fmt.bufPrint(string[written..], "}}\n", .{})).len;
        // },
      }
      return written;
    }
  };
};

const Parser = struct {
  const Self = @This();

  tokenizer: Tokenizer,

  pub fn init(buffer: [:0]const u8) Self {
    return Self {
      .tokenizer = Tokenizer.init(buffer),
    };
  }

  fn checkToken(self: *Self, token: Token, tag: Token.Tag, err: *GenericError) !void {
    if (token.tag != tag) {
      return makeError(ParseError.UnexpectedInput, getLocation(self.tokenizer.buffer, token.start),
        err, "expecting {s} got {s}", .{ @tagName(tag), @tagName(token.tag) });
    }
  }

  pub fn parse(self: *Self, err: *GenericError) !Ast.Node {
    const StatementLimit = 512;
    var program: [StatementLimit]Ast.Node = undefined;
    var declIndex: u16 = 0;

    while (true) {
      const token = try self.tokenizer.peek(err);
      switch (token.tag) {
        Token.Tag.comment => {}, // ignore
        Token.Tag.type => {
          program[declIndex] = try self.parseDeclaration(err);
          declIndex += 1;
        },
        Token.Tag.dot => { // field decl
          program[declIndex] = try self.parseFieldDefinition(err);
          declIndex += 1;
        },
        Token.Tag.eof => {
          if (declIndex == 0) {
            // Do not allow empty source file
            return makeError(ParseError.EmptySource, null, err, "Empty source file", .{});
          }
          return Ast.Node { .program = Ast.Program{
            .declarations = program[0..declIndex],
          } };
        },
        else => |t| return makeError(ParseError.UnexpectedInput, null, err, "Unexpected token {}", .{ t }),
      }
      if (declIndex >= StatementLimit) {
        return makeError(ParseError.EmptySource, null, err, "Too many statement. Limit is {}", .{ StatementLimit });
      }
    }
  }

  fn parseDeclaration(self: *Self, err: *GenericError) !Ast.Node {
    const typeToken = try self.tokenizer.next(err);
    const identifierToken = try self.tokenizer.peek(err);
    switch (identifierToken.tag) {
      Token.Tag.identifier => {
        return Ast.Node{ .var_decl = try self.parseVariableDefinition(typeToken, err) };
      },
      Token.Tag.l_paren => { // function declaration/definition
        return try self.parseFunctionDefinition(typeToken, err);
      },
      else => |t| return makeError(ParseError.EmptySource,
        getLocation(self.tokenizer.buffer, identifierToken.start), err,
        "Unexpected token {}", .{ t }),
    }
  }

  fn parseVariableDefinition(self: *Self, typeToken: Token, err: *GenericError) !Ast.VarDecl {
    const identifierToken = try self.tokenizer.next(err);
    if (identifierToken.tag != Token.Tag.identifier) {
      return makeError(ParseError.UnexpectedInput, getLocation(self.tokenizer.buffer, identifierToken.start), err,
        "expecting identifier found {}", .{ identifierToken });
    }
    const eqlToken = try self.tokenizer.next(err);
    switch (eqlToken.tag) {
      Token.Tag.equal => {
        const expression = try self.parseExpression(err);
        const scToken = try self.tokenizer.next(err);
        switch (scToken.tag) {
          Token.Tag.semicolon => {
            return Ast.VarDecl{
              .type = try Ast.QType.fromName(self.tokenizer.buffer[typeToken.start..typeToken.end + 1]),
              .name = self.tokenizer.buffer[identifierToken.start..identifierToken.end + 1],
              .value = expression,
            };
          },
          else => |t| return makeError(ParseError.EmptySource,
            getLocation(self.tokenizer.buffer, identifierToken.start), err,
            "Unexpected token {}", .{ t }),
        }
      },
      Token.Tag.semicolon => {
        return Ast.VarDecl{
          .type = try Ast.QType.fromName(self.tokenizer.buffer[typeToken.start..typeToken.end + 1]),
          .name = self.tokenizer.buffer[identifierToken.start..identifierToken.end + 1],
          .value = null,
        };
      },
      else => return makeError(ParseError.UnexpectedInput, getLocation(self.tokenizer.buffer, identifierToken.start), err,
        "expecting '=' or ';' found {}", .{ eqlToken }),
    }
  }

  fn parseFieldDefinition(self: *Self, err: *GenericError) !Ast.Node {
    // discard dot
    _ = try self.tokenizer.next(err);
    const typeToken = try self.tokenizer.next(err);
    const identifierToken = try self.tokenizer.next(err);
    if (identifierToken.tag != Token.Tag.identifier) {
      return makeError(ParseError.UnexpectedInput, getLocation(self.tokenizer.buffer, identifierToken.start), err,
        "expecting identifier found {}", .{ identifierToken });
    }
    const scToken = try self.tokenizer.next(err);
    if (scToken.tag != Token.Tag.semicolon) {
      return makeError(ParseError.UnexpectedInput, getLocation(self.tokenizer.buffer, identifierToken.start), err,
        "expecting semicolon found {}", .{ identifierToken });
    }
    return Ast.Node{ .field_decl = Ast.FieldDecl{
      .type = try Ast.QType.fromName(self.tokenizer.buffer[typeToken.start..typeToken.end + 1]),
      .name = self.tokenizer.buffer[identifierToken.start..identifierToken.end + 1],
    }};
  }

  fn parseExpression(self: *Self, err: *GenericError) !Ast.Expression {
    const token = try self.tokenizer.next(err);
    switch (token.tag) {
      Token.Tag.float_literal => {
        const value = try std.fmt.parseFloat(f32, self.tokenizer.buffer[token.start..token.end + 1]);
        return Ast.Expression{ .float_literal = Ast.FloatLiteral{ .value = value } };
      },
      Token.Tag.string_literal => {
        const value = self.tokenizer.buffer[token.start..token.end + 1];
        return Ast.Expression{ .string_literal = Ast.StringLiteral{ .value = value } };
      },
      Token.Tag.vector_literal => {
        const vectorLiteralStr = self.tokenizer.buffer[token.start..token.end + 1];
        const value = Ast.VectorLiteral.fromString(vectorLiteralStr) catch |e| {
          return makeError(e, getLocation(self.tokenizer.buffer, token.start), err,
            "incorrect vector literal", .{});
        };
        return Ast.Expression{ .vector_literal = value };
      },
      else => return makeError(ParseError.EmptySource, getLocation(self.tokenizer.buffer, token.start), err,
       "unexpected token {}", .{ token }),
    }
  }

  fn parseFunctionDefinition(self: *Self, typeToken: Token, err: *GenericError) !Ast.Node {
    // Retrieve the return type
    const atype = Ast.QType.fromName(self.tokenizer.buffer[typeToken.start..typeToken.end + 1]) catch |e| {
      return makeError(e, getLocation(self.tokenizer.buffer, typeToken.start), err,
        "Expecting a type got {s}", .{ self.tokenizer.buffer[typeToken.start..typeToken.end + 1] });
    };
    // pop l_paren
    _ = try self.tokenizer.next(err);
    // Create a temporary
    var fnDecl = Ast.FnDecl{
      .return_type = atype,
      .name = "",
      .parameter_list = &.{},
      .body = null,
    };
    // Peek at the next token
    var r_paren = try self.tokenizer.peek(err);
    var i: u16 = 0;
    // Parse the parameter declaration until we reach a r_paren
    while (r_paren.tag != Token.Tag.r_paren) : (i += 1) {
      fnDecl._storage[i] = try self.parseParamDeclaration(err);
      r_paren = try self.tokenizer.peek(err);
      // Ignore the comma but expect it
      if (r_paren.tag == Token.Tag.comma) _ = try self.tokenizer.next(err);
    }
    // Pop r_paren and expect the name of the function
    _ = try self.tokenizer.next(err);
    const identifierToken = try self.tokenizer.next(err);
    if (identifierToken.tag != Token.Tag.identifier) {
      return makeError(ParseError.UnexpectedInput, getLocation(self.tokenizer.buffer, identifierToken.start), err,
        "expecting function name found {}", .{ identifierToken });
    }
    fnDecl.name = self.tokenizer.buffer[identifierToken.start..identifierToken.end + 1];
    fnDecl.parameter_list = fnDecl._storage[0..i];
    // Now parse the body
    const bodyToken = try self.tokenizer.next(err);
    if (bodyToken.tag == Token.Tag.l_bracket) {
      // This is a frame specifier
      // TODO: Support frame specifier
      unreachable;
    }
    switch (bodyToken.tag) {
      Token.Tag.semicolon => {
        // We are dealing with a function declaration
        return Ast.Node{ .fn_decl = fnDecl };
      },
      Token.Tag.equal => {
        // We have a body
        const functionContentToken = try self.tokenizer.peek(err);
        switch (functionContentToken.tag) {
          Token.Tag.builtin_literal => {
            // This is a builtin declaration
            const builtinImmediateToken = try self.tokenizer.next(err);
            const scToken = try self.tokenizer.next(err);
            if (scToken.tag != Token.Tag.semicolon) {
              return makeError(ParseError.UnexpectedInput, getLocation(self.tokenizer.buffer, bodyToken.start), err,
                "expecting semicolon got {}", .{ bodyToken });
            }
            const bl = self.tokenizer.buffer[builtinImmediateToken.start + 1..builtinImmediateToken.end + 1];
            var bDecl = Ast.BuiltinDecl{
              .return_type = atype,
              .name = fnDecl.name,
              .parameter_list = &.{},
              .index = try std.fmt.parseInt(u16, bl, 10),
              ._storage = fnDecl._storage,
            };
            bDecl.parameter_list = bDecl._storage[0..i];
            return Ast.Node{ .builtin_decl = bDecl };
          },
          Token.Tag.l_brace => {
            // This is a statement list
            fnDecl.body = Ast.Body{ .statement_list = try self.parseStatement(err) };
            return Ast.Node{ .fn_decl = fnDecl };
          },
          else => {
            // This is an expression
            const expression = try self.parseExpression(err);
            fnDecl.body = Ast.Body{ .statement_list = &.{ Ast.Statement{ .expression = expression } } };
            return Ast.Node{ .fn_decl = fnDecl };
          }
        }
      },
      else => {},
    }

    return makeError(ParseError.UnexpectedInput, getLocation(self.tokenizer.buffer, bodyToken.start), err,
      "expecting function body {}", .{ bodyToken });
  }

  fn parseStatement(self: *Self, err: *GenericError) ![]Ast.Statement {
    const l_brace = try self.tokenizer.next(err);
    try self.checkToken(l_brace, Token.Tag.l_brace, err);
    var r_brace = try self.tokenizer.peek(err);
    while (r_brace.tag != Token.Tag.r_brace) {
      // TODO
      r_brace = try self.tokenizer.peek(err);
    }
    // pop r_brace
    _ = try self.tokenizer.next(err);
    return &.{};
  }

  fn parseParamDeclaration(self: *Self, err: *GenericError) !Ast.ParamDecl {
    const typeToken = try self.tokenizer.next(err);
    if (typeToken.tag == Token.Tag.elipsis) {
      return Ast.ParamDecl{ .param = .elipsis };
    }
    const atype = Ast.QType.fromName(self.tokenizer.buffer[typeToken.start..typeToken.end + 1]) catch |e| {
      return makeError(e, getLocation(self.tokenizer.buffer, typeToken.start), err,
        "Expecting a type got {s}", .{ self.tokenizer.buffer[typeToken.start..typeToken.end + 1] });
    };
    const identifierToken = try self.tokenizer.next(err);
    if (identifierToken.tag != Token.Tag.identifier) {
      return makeError(ParseError.UnexpectedInput, getLocation(self.tokenizer.buffer, identifierToken.start), err,
        "expecting identifier found {}", .{ identifierToken });
    }
    const name = self.tokenizer.buffer[identifierToken.start..identifierToken.end + 1];
    return Ast.ParamDecl{ .param = .{ .declaration = .{ .type = atype, .name = name } } };
  }
};

fn testTokenize(source: [:0]const u8, expected_token_tags: []const Token.Tag, err: *GenericError) !void {
  var tokenizer = Tokenizer.init(source);
  for (expected_token_tags) |expected_token_tag| {
      const token = try tokenizer.next(err);
      try std.testing.expectEqual(expected_token_tag, token.tag);
  }
  const last_token = try tokenizer.next(err);
  try std.testing.expectEqual(Token.Tag.eof, last_token.tag);
  try std.testing.expectEqual(source.len, last_token.start);
  try std.testing.expectEqual(source.len, last_token.end);
}

test "tokenizer test" {
  var err = GenericError{};
  try testTokenize("(this is an_identifier)", &.{
    Token.Tag.l_paren,
    Token.Tag.identifier,
    Token.Tag.identifier,
    Token.Tag.identifier,
    Token.Tag.r_paren,
    Token.Tag.eof,
  }, &err);
  try testTokenize(".vector field;", &.{
    Token.Tag.dot,
    Token.Tag.type,
    Token.Tag.identifier,
    Token.Tag.semicolon,
    Token.Tag.eof,
  }, &err);
  try testTokenize("float f = 3.14;", &.{
    Token.Tag.type,
    Token.Tag.identifier,
    Token.Tag.equal,
    Token.Tag.float_literal,
    Token.Tag.semicolon,
    Token.Tag.eof,
  }, &err);
  try testTokenize("string s = \"pi\";", &.{
    Token.Tag.type,
    Token.Tag.identifier,
    Token.Tag.equal,
    Token.Tag.string_literal,
    Token.Tag.semicolon,
    Token.Tag.eof,
  }, &err);
  try testTokenize("vector v = '+0.5 -1 -.2';", &.{
    Token.Tag.type,
    Token.Tag.identifier,
    Token.Tag.equal,
    Token.Tag.vector_literal,
    Token.Tag.semicolon,
    Token.Tag.eof,
  }, &err);
  try testTokenize("void (float f, vector v) foo = {}", &.{
    Token.Tag.type,
    Token.Tag.l_paren,
    Token.Tag.type,
    Token.Tag.identifier,
    Token.Tag.comma,
    Token.Tag.type,
    Token.Tag.identifier,
    Token.Tag.r_paren,
    Token.Tag.identifier,
    Token.Tag.equal,
    Token.Tag.l_brace,
    Token.Tag.r_brace,
    Token.Tag.eof,
  }, &err);
  try testTokenize("void\t(string str, ...)\tprint = #99;", &.{
    Token.Tag.type,
    Token.Tag.l_paren,
    Token.Tag.type,
    Token.Tag.identifier,
    Token.Tag.comma,
    Token.Tag.elipsis,
    Token.Tag.r_paren,
    Token.Tag.identifier,
    Token.Tag.equal,
    Token.Tag.builtin_literal,
    Token.Tag.semicolon,
    Token.Tag.eof,
  }, &err);

  const comments =
    \\ // Let's describe this function
    \\ void () main = {
    \\   string foo = "foo";
    \\   printf(foo); // prints foo
    \\ }
  ;
  try testTokenize(comments, &.{
    Token.Tag.comment,
    Token.Tag.type,
    Token.Tag.l_paren,
    Token.Tag.r_paren,
    Token.Tag.identifier,
    Token.Tag.equal,
    Token.Tag.l_brace,
    Token.Tag.type,
    Token.Tag.identifier,
    Token.Tag.equal,
    Token.Tag.string_literal,
    Token.Tag.semicolon,
    Token.Tag.identifier,
    Token.Tag.l_paren,
    Token.Tag.identifier,
    Token.Tag.r_paren,
    Token.Tag.semicolon,
    Token.Tag.comment,
    Token.Tag.r_brace,
    Token.Tag.eof,
  }, &err);

  const conditions =
    \\if ("foo" == "foo" && 1 != 2 || false && true) {
    \\  printf(foo);
    \\}
  ;
  try testTokenize(conditions, &.{
    Token.Tag.kw_if,
    Token.Tag.l_paren,
    Token.Tag.string_literal,
    Token.Tag.double_equal,
    Token.Tag.string_literal,
    Token.Tag.and_,
    Token.Tag.float_literal,
    Token.Tag.not_equal,
    Token.Tag.float_literal,
    Token.Tag.or_,
    Token.Tag.false,
    Token.Tag.and_,
    Token.Tag.true,
    Token.Tag.r_paren,
    Token.Tag.l_brace,
    Token.Tag.identifier,
    Token.Tag.l_paren,
    Token.Tag.identifier,
    Token.Tag.r_paren,
    Token.Tag.semicolon,
    Token.Tag.r_brace,
    Token.Tag.eof,
  }, &err);
}

fn expectEqualString(lhs: []const u8, rhs: []const u8) !void {
  if (std.mem.eql(u8, lhs, rhs)) {
    return;
  } else {
    std.log.err("\n\"{s}\" ({}) \n not equal to\n\"{s}\" ({})", .{ lhs, lhs.len, rhs, rhs.len });
    return error.Fail;
  }
}

fn testParse(source: [:0]const u8, err: *GenericError) !void {
  var output: [4096:0]u8 = .{ 0 } ** 4096;
  var parser = Parser.init(source);
  const node = try parser.parse(err);
  _ = try node.prettyPrint(&output);
  try expectEqualString(source, std.mem.span(@as([*:0]const u8, @ptrCast(&output))));
}

test "parser test" {
  var err = GenericError{};
  try testParse("float f = 3.14;", &err);
  try testParse("float f;", &err);
  try testParse("string s = \"foo\";", &err);
  try testParse("vector v = '1 2 3';", &err);
  try testParse(".vector vectorField;", &err);
  try testParse("void () foo;", &err);
  try testParse("void () foo = #42;", &err);
  try testParse("void (string s) foo;", &err);
  try testParse("void (string s, ...) foo;", &err);
  try testParse("void () main = {}", &err);
  try testParse("void (float f, vector v) main = {}", &err);
}
