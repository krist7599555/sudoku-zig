const std = @import("std");

pub const GRID_SIZE = 9;
pub const CELL_COUNT = 81;
pub const FULL_MASK: u16 = 0b111_111_111;

pub const SudokuError = error{
    InvalidLength,
    InvalidChar,
    DuplicatedElement,
};

/// Returns a bitmask for a Sudoku value (1-9).
/// Value 0 returns 0.
pub inline fn get_bitmask(val: u8) u16 {
    std.debug.assert(val <= 9);
    return if (val == 0) 0 else @as(u16, 1) << @intCast(val - 1);
}

const BitmaskIterator = struct {
    mask: u16 = 0,
    fn next(self: *@This()) ?u8 {
        if (self.mask > 0) {
            const out: u8 = @intCast(@ctz(self.mask));
            self.mask &= self.mask - 1;
            return out;
        }
        return null;
    }
};
const Bitmask = struct {
    mask: u16 = 0,
    pub fn len(self: *const Bitmask) u8 {
        return @popCount(self.mask);
    }
    pub fn has(self: *const Bitmask, val: u8) bool {
        return (self.mask & (get_bitmask(val))) == get_bitmask(val);
    }
    pub fn iter(self: *const Bitmask) BitmaskIterator {
        return BitmaskIterator{ .mask = self.mask };
    }
};

pub const Sudoku = struct {
    table: [CELL_COUNT]u8,
    row_masks: [GRID_SIZE]u16,
    col_masks: [GRID_SIZE]u16,
    box_masks: [GRID_SIZE]u16,

    // ## CONSTRUCTOR

    pub fn create() Sudoku {
        return .{
            .table = .{0} ** CELL_COUNT,
            .row_masks = .{0} ** GRID_SIZE,
            .col_masks = .{0} ** GRID_SIZE,
            .box_masks = .{0} ** GRID_SIZE,
        };
    }

    pub fn generate_puzzle(rng: std.Random) struct { expect: Sudoku, input: Sudoku } {
        var completed = Sudoku.create();
        _ = completed.inplace_random_fill(rng, 0);
        var pruned = completed;
        _ = pruned.inplace_prune_cells(rng);
        return .{ .expect = completed, .input = pruned };
    }

    // ## CODEC<string>

    pub fn from_string(str: []const u8) SudokuError!Sudoku {
        if (str.len != CELL_COUNT) return SudokuError.InvalidLength;
        var self = Sudoku.create();
        for (str, 0..) |c, i| {
            switch (c) {
                '1'...'9' => {
                    const val = c - '0';
                    if (!self.get_possible_moves(i).has(val)) return SudokuError.DuplicatedElement;
                    self.set_cell(i, val);
                },
                '0', '.' => {},
                else => return SudokuError.InvalidChar,
            }
        }
        return self;
    }

    pub fn to_string(self: *const Sudoku) [CELL_COUNT]u8 {
        var str: [CELL_COUNT]u8 = undefined;
        for (self.table, 0..) |v, i| {
            str[i] = if (v == 0) '.' else v + '0';
        }
        return str;
    }

    pub fn pretty_string(self: *const Sudoku) [609]u8 {
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
        @memcpy(&out, template);

        var cell_idx: usize = 0;
        for (template, 0..) |c, char_idx| {
            if (c != '.') continue;
            const val = self.table[cell_idx];
            out[char_idx] = if (val == 0) '.' else val + '0';
            cell_idx += 1;
        }
        return out;
    }

    // ## Mask Helper

    inline fn tor(idx: usize) usize {
        return (idx / 9);
    }
    inline fn toc(idx: usize) usize {
        return (idx % 9);
    }
    inline fn tob(idx: usize) usize {
        return (idx / 27) * 3 + (idx % 9) / 3;
    }

    // ## Cell Helper

    fn set_cell(self: *Sudoku, idx: usize, val: u8) void {
        const m = get_bitmask(val);
        self.table[idx] = val;
        self.row_masks[tor(idx)] |= m;
        self.col_masks[toc(idx)] |= m;
        self.box_masks[tob(idx)] |= m;
    }
    fn clear_cell(self: *Sudoku, idx: usize) void {
        const val = self.table[idx];
        if (val == 0) return;
        const m = get_bitmask(val);
        self.row_masks[tor(idx)] &= ~m;
        self.col_masks[toc(idx)] &= ~m;
        self.box_masks[tob(idx)] &= ~m;
        self.table[idx] = 0;
    }

    // ## Bitmask

    fn get_possible_moves(self: *const Sudoku, idx: usize) Bitmask {
        const used = self.row_masks[tor(idx)] |
            self.col_masks[toc(idx)] |
            self.box_masks[tob(idx)];
        return Bitmask{ .mask = FULL_MASK & ~used };
    }

    // ## CHECKER

    pub fn is_solved(self: *const Sudoku) bool {
        for (self.table) |val| if (val == 0) return false;
        for (0..GRID_SIZE) |i| {
            if (self.row_masks[i] != FULL_MASK or
                self.col_masks[i] != FULL_MASK or
                self.box_masks[i] != FULL_MASK) return false;
        }
        return true;
    }

    // ## Modifier

    fn inplace_random_fill(self: *Sudoku, rng: std.Random, cell_idx: usize) bool {
        if (cell_idx == CELL_COUNT) return true;
        std.debug.assert(self.table[cell_idx] == 0);

        var values = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
        rng.shuffle(u8, &values);

        for (values) |val| {
            if (self.get_possible_moves(cell_idx).has(val)) {
                self.set_cell(cell_idx, val);
                if (self.inplace_random_fill(rng, cell_idx + 1)) return true;
                self.clear_cell(cell_idx);
            }
        }
        return false;
    }

    fn inplace_prune_cells(self: *Sudoku, rng: std.Random) void {
        var indices: [CELL_COUNT]u8 = undefined;
        for (0..CELL_COUNT) |i| indices[i] = @intCast(i);
        rng.shuffle(u8, &indices);

        for (indices) |idx| {
            const original_val = self.table[idx];
            self.clear_cell(idx);
            // Heuristic: only keep the cell empty if it still has a unique move
            // in its immediate context.
            if (self.get_possible_moves(idx).len() > 1) { // ans is not unique -> reverse
                self.set_cell(idx, original_val);
            }
        }
    }

    pub fn inplace_solve(self: *Sudoku) bool {
        var min_sz: usize = 10;
        var min_idx: usize = 81;
        var min_mask: ?Bitmask = null;
        for (0..81) |idx| {
            if (self.table[idx] != 0) continue;
            const mask = self.get_possible_moves(idx);
            if (mask.len() == 0) return false; // after previous update -> unsolveable
            if (mask.len() < min_sz) {
                min_sz = mask.len();
                min_idx = idx;
                min_mask = mask;
            }
        }

        const mask = min_mask orelse return true;
        var it = mask.iter();
        while (it.next()) |_val| {
            const val = _val + 1;
            std.debug.assert(1 <= val and val <= 9);
            self.set_cell(min_idx, val);
            if (self.inplace_solve()) return true;
            self.clear_cell(min_idx);
        }
        return false;
    }
};

pub fn solve(input: []const u8) SudokuError![CELL_COUNT]u8 {
    var self = try Sudoku.from_string(input);
    if (!self.inplace_solve()) return SudokuError.DuplicatedElement;
    return self.to_string();
}

pub fn generate_puzzle(rng: std.Random) struct { expect: [CELL_COUNT]u8, input: [CELL_COUNT]u8 } {
    const gen = Sudoku.generate_puzzle(rng);
    return .{
        .expect = gen.expect.to_string(),
        .input = gen.input.to_string(),
    };
}

pub export fn abi_solve(input: [*]const u8, output: [*]u8) i32 {
    const out = solve(input[0..CELL_COUNT]) catch return -1;
    @memcpy(output[0..CELL_COUNT], &out);
    return 0;
}

pub export fn abi_generate_puzzle(seed: u64, solved: [*]u8, puzzle: [*]u8) i32 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    const out = generate_puzzle(rng);
    @memcpy(solved[0..CELL_COUNT], &out.expect);
    @memcpy(puzzle[0..CELL_COUNT], &out.input);
    return 0;
}

test "generated puzzle should be solvable" {
    var prng = std.Random.DefaultPrng.init(0xdeadbeef);
    const rng = prng.random();
    const gen = Sudoku.generate_puzzle(rng);
    var puzzle = gen.input;
    const ok = puzzle.inplace_solve();
    try std.testing.expect(ok);
    try std.testing.expect(puzzle.is_solved());
    try std.testing.expectEqualSlices(u8, &gen.expect.table, &puzzle.table);
}

test "generated puzzle should be solvable 2" {
    var prng = std.Random.DefaultPrng.init(0xdeadbeef);
    const rng = prng.random();
    const gen = generate_puzzle(rng);
    const out = try solve(&gen.input);
    try std.testing.expectEqualSlices(u8, &gen.expect, &out);
}

test "sudoku solver should solve known puzzles" {
    const cases = [_][]const u8{
        "7...2654..98.75.2...5.4.97198.6.275.....87.1934.5....26592..4...34.6..85..235.1..",
        "000000009002004700100000080000302006003007500600005000090040001006700200800000060",
        "300000700010009005004000020000502000000048001080960000200000040007000300090050008",
        "4.....8.5.3..........7......2.....6.....8.4......1.......6.3.7.5..2.....1.4......",
        "100007090030020008009600500005300900010080002600004000300000010040000007007000300",
        "800000000003600000070090200050007000000045700000100030001000068008500010090000400",
        "005300000800000020070010500400005300010070006003200080060500009004000030000009700",
        "500000009020100070008000300040002000000050000000706010003000800060004020900000005",
        "000000039000010005003005800008009006070020000100400000009008050020000600400700000",
        ".................................................................................",
        "162857493534129678789643521475312986913586742628794135356478219241935867897261354",
        "417369825632158947958724316825437169791586432346912758289643571573291684164875293",
    };
    for (cases) |case| {
        var self = try Sudoku.from_string(case);
        try std.testing.expect(self.inplace_solve());
        try std.testing.expect(self.is_solved());
    }
}

test "sudoku solve basic string" {
    const output = try solve("7...2654..98.75.2...5.4.97198.6.275.....87.1934.5....26592..4...34.6..85..235.1..");
    const self = try Sudoku.from_string(&output);
    try std.testing.expect(self.is_solved());
}

test "sudoku solve invalid input.len" {
    try std.testing.expectError(SudokuError.InvalidLength, solve("invalid"));
    try std.testing.expectError(SudokuError.InvalidLength, solve(""));
    try std.testing.expectError(SudokuError.InvalidLength, solve("1" ** 82));
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
