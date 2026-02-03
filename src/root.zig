const std = @import("std");

pub const MIN_NUM = 1;
pub const MAX_NUM = 9;
pub const TABLE_SIZE = 81;
const Table = [TABLE_SIZE]u8;

pub inline fn bitmask(val: u8) u16 {
    std.debug.assert(val <= 9);
    return if (val == 0) 0 else @as(u16, 1) << @intCast(val - 1);
}

pub const SudokuError = error{
    InvalidLength,
    InvalidChar,
    DuplicatedElement,
};

pub const Sudoku = struct {
    table: [81]u8,
    row: [9]u16,
    col: [9]u16,
    box: [9]u16,

    const FULLMASK: u16 = 0b111_111_111;

    pub fn init() Sudoku {
        return .{
            .table = .{0} ** 81,
            .row = .{0b000_000_000} ** 9,
            .col = .{0b000_000_000} ** 9,
            .box = .{0b000_000_000} ** 9,
        };
    }
    pub fn generateSolved(rng: std.Random) Sudoku {
        var sudok = Sudoku.init();
        const valid = sudok._generateSolved(rng, 0);
        std.debug.assert(valid);
        return sudok;
    }
    pub fn generateSolvedPuzzle(rng: std.Random) struct { solved: Sudoku, puzzle: Sudoku } {
        const solved = generateSolved(rng);
        var puzzle = solved;
        puzzle._pruneCells(rng);
        return .{ .solved = solved, .puzzle = puzzle };
    }
    pub fn generatePuzzle(rng: std.Random) Sudoku {
        return generateSolvedPuzzle(rng).puzzle;
    }
    fn _generateSolved(table: *Sudoku, rng: std.Random, idx: usize) bool {
        if (idx == TABLE_SIZE) return true;
        std.debug.assert(table.table[idx] == 0);
        var values = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
        rng.shuffle(u8, &values);
        for (values) |val| {
            if (table.canSet(idx, val)) {
                table.set(idx, val);
                if (table._generateSolved(rng, idx + 1)) {
                    return true;
                }
                table.unset(idx);
            }
        }
        return false;
    }
    fn _pruneCells(table: *Sudoku, rng: std.Random) void {
        for (table.table) |val| {
            // table must be all set
            std.debug.assert(val > 0);
        }
        var values: [81]u8 = undefined;
        for (0..81) |i| {
            values[i] = @intCast(i);
        }
        rng.shuffle(u8, &values);
        for (values) |idx| {
            const memoVal = table.table[idx];
            table.unset(idx);
            if (@popCount(table.validMove(idx)) == 1) { // still have unique answer
                continue;
            }
            table.set(idx, memoVal);
        }
    }
    pub fn fromString(str: []const u8) SudokuError!Sudoku {
        if (str.len != 81) return SudokuError.InvalidLength;
        var res = Sudoku.init();
        for (str, 0..) |c, i| {
            switch (c) {
                '1'...'9' => {
                    const val = c - '0';
                    if (!res.canSet(i, val)) {
                        return SudokuError.DuplicatedElement;
                    }
                    res.set(i, val);
                },
                '0', '.' => {},
                else => return SudokuError.InvalidChar,
            }
        }
        return res;
    }
    pub fn toString(self: *const Sudoku) [81]u8 {
        var str: [81]u8 = undefined;
        for (self.table, 0..) |v, i| {
            str[i] = switch (v) {
                0 => '.',
                1...9 => v + '0',
                else => @panic("not match val"),
            };
        }
        return str;
    }
    pub fn prettyString(self: *const Sudoku) [609]u8 {
        const template =
            \\┌───────┬───────┬───────┐
            \\│ . . . │ . . . │ . . . │
            \\│ . . . │ . . . │ . . . │
            \\│ . . . │ . . . │ . . . │
            \\├───────┼───────┼───────┤
            \\│ . . . │ . . . │ . . . │
            \\│ . . . │ . . . │ . . . │
            \\│ . . . │ . . . │ . . . │
            \\├───────┼───────┼───────┤
            \\│ . . . │ . . . │ . . . │
            \\│ . . . │ . . . │ . . . │
            \\│ . . . │ . . . │ . . . │
            \\└───────┴───────┴───────┘
        ;
        var out: [template.len]u8 = undefined;
        std.mem.copyForwards(u8, out[0..template.len], template);

        var i: usize = 0;
        for (template, 0..) |c, idx| {
            if (c != '.') continue;
            const v = self.table[i];
            i += 1;
            out[idx] = switch (v) {
                0 => '.',
                1...9 => v + '0',
                else => @panic("not match val"),
            };
        }

        return out;
    }
    inline fn tor(idx: usize) usize {
        return (idx / 9);
    }
    inline fn toc(idx: usize) usize {
        return (idx % 9);
    }
    inline fn tob(idx: usize) usize {
        return (idx / 27) * 3 + (idx % 9) / 3;
    }
    fn set(self: *Sudoku, idx: usize, val: u8) void {
        std.debug.assert(val > 0);
        if (self.table[idx] > 0) self.unset(idx);
        const m = bitmask(val);
        self.table[idx] = val;
        self.row[tor(idx)] |= m;
        self.col[toc(idx)] |= m;
        self.box[tob(idx)] |= m;
    }
    fn unset(self: *Sudoku, idx: usize) void {
        if (self.table[idx] == 0) return;
        std.debug.assert(self.table[idx] > 0);
        const m = bitmask(self.table[idx]);
        self.row[tor(idx)] &= ~m;
        self.col[toc(idx)] &= ~m;
        self.box[tob(idx)] &= ~m;
        self.table[idx] = 0;
    }
    fn validMove(self: *const Sudoku, idx: usize) u16 {
        return Sudoku.FULLMASK & ~(0b0 |
            self.row[tor(idx)] |
            self.col[toc(idx)] |
            self.box[tob(idx)]);
    }
    fn canSet(self: *Sudoku, idx: usize, val: u8) bool {
        if (self.table[idx] == val) return true;
        if (self.table[idx] != val and self.table[idx] > 0) return false;
        if ((self.validMove(idx) & bitmask(val)) > 0) {
            return true;
        }
        return false;
    }
    pub fn isSolved(self: *const Sudoku) bool {
        for (self.table) |val| {
            if (val == 0) return false;
        }
        const masks = [_][]const u16{ self.row[0..], self.col[0..], self.box[0..] };
        for (masks) |arr| {
            for (arr[0..9]) |mask| {
                if (mask != 0b111_111_111) {
                    return false;
                }
            }
        }
        return true;
    }

    pub fn solve(self: *Sudoku) bool {
        var minSz: usize = 10;
        var minIdx: usize = 81;
        var minMask: u16 = 0b00;
        for (0..81) |idx| {
            if (self.table[idx] != 0) continue;
            const mask = Sudoku.FULLMASK & ~(0b0 |
                self.row[tor(idx)] |
                self.col[toc(idx)] |
                self.box[tob(idx)]);
            const sz = @popCount(mask);
            if (sz == 0) return false; // after previous update -> unsolveable
            std.debug.assert(sz > 0);
            if (sz < minSz) {
                minSz = sz;
                minIdx = idx;
                minMask = mask;
            }
        }
        if (minSz == 10) return true; // every thing is filled
        while (minMask > 0) {
            const val = @ctz(minMask) + 1;
            std.debug.assert(1 <= val and val <= 9);
            minMask &= minMask - 1;
            self.set(minIdx, val);
            if (self.solve()) {
                return true;
            }
            self.unset(minIdx);
        }
        return false;
    }
};

pub fn solve(input: []const u8) SudokuError![81]u8 {
    var sudok = try Sudoku.fromString(input);
    const solved = sudok.solve();
    std.debug.assert(solved);
    return sudok.toString();
}

pub fn generate_solved_puzzle(rng: std.Random) struct { solved: [81]u8, puzzle: [81]u8 } {
    var out = Sudoku.generateSolvedPuzzle(rng);
    return .{
        .solved = out.solved.toString(),
        .puzzle = out.puzzle.toString(),
    };
}

pub export fn abi_solve(input: [*]const u8, output: [*]u8) i32 {
    const out = solve(input[0..81]) catch return -1;
    std.mem.copyForwards(u8, output[0..81], &out);
    return 0;
}
pub export fn abi_generate_solved_puzzle(seed: u64, solved: [*]u8, puzzle: [*]u8) i32 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    const out = generate_solved_puzzle(rng);
    std.mem.copyForwards(u8, solved[0..81], &out.solved);
    std.mem.copyForwards(u8, puzzle[0..81], &out.puzzle);
    return 0;
}

test "generated puzzle should be solvable" {
    var prng = std.Random.DefaultPrng.init(0xdeadbeef);
    const rng = prng.random();
    const gen = Sudoku.generateSolvedPuzzle(rng);
    var puzzle = gen.puzzle;
    const ok = puzzle.solve();
    try std.testing.expect(ok);
    try std.testing.expect(puzzle.isSolved());
    try std.testing.expectEqual(gen.solved, puzzle);
}

test "generated puzzle should be solvable 2" {
    var prng = std.Random.DefaultPrng.init(0xdeadbeef);
    const rng = prng.random();
    const gen = generate_solved_puzzle(rng);
    const out = try solve(&gen.puzzle);
    try std.testing.expectEqual(gen.solved, out);
}

test "sudoku solver should solve known puzzles" {
    const cases = [_]Sudoku{
        // Simple Problem
        try Sudoku.fromString("7...2654..98.75.2...5.4.97198.6.275.....87.1934.5....26592..4...34.6..85..235.1.."),
        try Sudoku.fromString("000000009002004700100000080000302006003007500600005000090040001006700200800000060"),
        try Sudoku.fromString("300000700010009005004000020000502000000048001080960000200000040007000300090050008"),
        // AI-Generated Hardest List: A frequently cited set of 11,000+ extremely hard puzzles found by researchers, often starting with puzzles like
        try Sudoku.fromString("4.....8.5.3..........7......2.....6.....8.4......1.......6.3.7.5..2.....1.4......"),
        // #3) AI Escagot 2006 {Se 10.4} { solved this one one here needs an AA MSLS }
        try Sudoku.fromString("100007090030020008009600500005300900010080002600004000300000010040000007007000300"),
        // #2) AI Everest 2010: SE 10.6 https://www.reddit.com/r/sudoku/comments/12bbt5z/deleted_by_user/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
        try Sudoku.fromString("800000000003600000070090200050007000000045700000100030001000068008500010090000400"),
        // #1) AI Etana (2010): se 10.6
        try Sudoku.fromString("005300000800000020070010500400005300010070006003200080060500009004000030000009700"),
        // rated SE 11.6 (Escargot is 10.7 for comparison)
        try Sudoku.fromString("500000009020100070008000300040002000000050000000706010003000800060004020900000005"),
        // Golden Nugget
        try Sudoku.fromString("000000039000010005003005800008009006070020000100400000009008050020000600400700000"),
        // Empty
        try Sudoku.fromString("................................................................................."),
        // Already Solved
        try Sudoku.fromString("162857493534129678789643521475312986913586742628794135356478219241935867897261354"),
        try Sudoku.fromString("417369825632158947958724316825437169791586432346912758289643571573291684164875293"),
    };

    for (cases, 0..) |puzzle, i| {
        var solved = puzzle; // clone
        const ok = solved.solve();
        try std.testing.expect(ok);
        try std.testing.expect(solved.isSolved());
        _ = i;
    }
}

test "sudoku solve basic string" {
    const output = try solve("7...2654..98.75.2...5.4.97198.6.275.....87.1934.5....26592..4...34.6..85..235.1..");
    const table = try Sudoku.fromString(&output);
    try std.testing.expect(table.isSolved());
}
test "sudoku solve invalid input.len" {
    try std.testing.expectError(SudokuError.InvalidLength, solve("invalid"));
    try std.testing.expectError(SudokuError.InvalidLength, solve(""));
    try std.testing.expectError(SudokuError.InvalidLength, solve("11234567891234567891234567891234567891234567891234567891234567891234567891234567899"));
}
test "sudoku solve invalid input.char" {
    try std.testing.expectError(SudokuError.InvalidChar, solve("A23456789123456789123456789123456789123456789123456789123456789123456789123456789"));
    try std.testing.expectError(SudokuError.InvalidChar, solve("##3456789123456789123456789123456789123456789123456789123456789123456789123456789"));
    try std.testing.expectError(SudokuError.InvalidChar, solve(" #3456789123456789123456789123456789123456789123456789123456789123456789123456789"));
}
test "sudoku solve conflict" {
    try std.testing.expectError(SudokuError.DuplicatedElement, solve("222444789123456789123456789123456789123456789123456789123456789123456789123456789"));
    try std.testing.expectError(SudokuError.DuplicatedElement, solve("1.........1......................................................................"));
}
