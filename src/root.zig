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

pub const Sudoku = struct {
    table: [CELL_COUNT]u8,
    row_masks: [GRID_SIZE]u16,
    col_masks: [GRID_SIZE]u16,
    box_masks: [GRID_SIZE]u16,

    pub fn init() Sudoku {
        return .{
            .table = .{0} ** CELL_COUNT,
            .row_masks = .{0} ** GRID_SIZE,
            .col_masks = .{0} ** GRID_SIZE,
            .box_masks = .{0} ** GRID_SIZE,
        };
    }

    pub fn generate_solved(rng: std.Random) Sudoku {
        var self = Sudoku.init();
        const success = self.fill_randomly(rng, 0);
        std.debug.assert(success);
        return self;
    }

    pub fn generate_solved_puzzle(rng: std.Random) struct { solved: Sudoku, puzzle: Sudoku } {
        const solved = generate_solved(rng);
        var puzzle = solved;
        puzzle.prune_cells(rng);
        return .{ .solved = solved, .puzzle = puzzle };
    }

    fn fill_randomly(self: *Sudoku, rng: std.Random, cell_idx: usize) bool {
        if (cell_idx == CELL_COUNT) return true;
        std.debug.assert(self.table[cell_idx] == 0);

        var values = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
        rng.shuffle(u8, &values);

        for (values) |val| {
            if (self.is_move_valid(cell_idx, val)) {
                self.set_cell(cell_idx, val);
                if (self.fill_randomly(rng, cell_idx + 1)) return true;
                self.clear_cell(cell_idx);
            }
        }
        return false;
    }

    fn prune_cells(self: *Sudoku, rng: std.Random) void {
        var indices: [CELL_COUNT]u8 = undefined;
        for (0..CELL_COUNT) |i| indices[i] = @intCast(i);
        rng.shuffle(u8, &indices);

        for (indices) |idx| {
            const original_val = self.table[idx];
            self.clear_cell(idx);
            // Heuristic: only keep the cell empty if it still has a unique move
            // in its immediate context.
            if (@popCount(self.get_possible_moves_mask(idx)) != 1) {
                self.set_cell(idx, original_val);
            }
        }
    }

    pub fn from_string(str: []const u8) SudokuError!Sudoku {
        if (str.len != CELL_COUNT) return SudokuError.InvalidLength;
        var self = Sudoku.init();
        for (str, 0..) |c, i| {
            switch (c) {
                '1'...'9' => {
                    const val = c - '0';
                    if (!self.is_move_valid(i, val)) return SudokuError.DuplicatedElement;
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

    inline fn tor(idx: usize) usize {
        return (idx / 9);
    }
    inline fn toc(idx: usize) usize {
        return (idx % 9);
    }
    inline fn tob(idx: usize) usize {
        return (idx / 27) * 3 + (idx % 9) / 3;
    }

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

    fn get_possible_moves_mask(self: *const Sudoku, idx: usize) u16 {
        const used = self.row_masks[tor(idx)] |
            self.col_masks[toc(idx)] |
            self.box_masks[tob(idx)];
        return FULL_MASK & ~used;
    }

    fn is_move_valid(self: *const Sudoku, idx: usize, val: u8) bool {
        if (self.table[idx] == val) return true;
        if (self.table[idx] != 0) return false;
        return (self.get_possible_moves_mask(idx) & get_bitmask(val)) != 0;
    }

    pub fn is_solved(self: *const Sudoku) bool {
        for (self.table) |val| if (val == 0) return false;
        for (0..GRID_SIZE) |i| {
            if (self.row_masks[i] != FULL_MASK or
                self.col_masks[i] != FULL_MASK or
                self.box_masks[i] != FULL_MASK) return false;
        }
        return true;
    }

    pub fn solve(self: *Sudoku) bool {
        var min_sz: usize = 10;
        var min_idx: usize = 81;
        var min_mask: u16 = 0b00;
        for (0..81) |idx| {
            if (self.table[idx] != 0) continue;
            const mask = FULL_MASK & ~(0b0 |
                self.row_masks[tor(idx)] |
                self.col_masks[toc(idx)] |
                self.box_masks[tob(idx)]);
            const sz = @popCount(mask);
            if (sz == 0) return false; // after previous update -> unsolveable
            std.debug.assert(sz > 0);
            if (sz < min_sz) {
                min_sz = sz;
                min_idx = idx;
                min_mask = mask;
            }
        }
        if (min_sz == 10) return true; // every thing is filled
        while (min_mask > 0) {
            const val = @ctz(min_mask) + 1;
            std.debug.assert(1 <= val and val <= 9);
            min_mask &= min_mask - 1;
            self.set_cell(min_idx, val);
            if (self.solve()) {
                return true;
            }
            self.clear_cell(min_idx);
        }
        return false;
    }
};

pub fn solve(input: []const u8) SudokuError![CELL_COUNT]u8 {
    var self = try Sudoku.from_string(input);
    if (!self.solve()) return SudokuError.DuplicatedElement;
    return self.to_string();
}

pub fn generate_solved_puzzle_top(rng: std.Random) struct { solved: [CELL_COUNT]u8, puzzle: [CELL_COUNT]u8 } {
    const gen = Sudoku.generate_solved_puzzle(rng);
    return .{
        .solved = gen.solved.to_string(),
        .puzzle = gen.puzzle.to_string(),
    };
}

pub export fn abi_solve(input: [*]const u8, output: [*]u8) i32 {
    const out = solve(input[0..CELL_COUNT]) catch return -1;
    @memcpy(output[0..CELL_COUNT], &out);
    return 0;
}

pub export fn abi_generate_solved_puzzle(seed: u64, solved: [*]u8, puzzle: [*]u8) i32 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    const out = generate_solved_puzzle_top(rng);
    @memcpy(solved[0..CELL_COUNT], &out.solved);
    @memcpy(puzzle[0..CELL_COUNT], &out.puzzle);
    return 0;
}

test "generated puzzle should be solvable" {
    var prng = std.Random.DefaultPrng.init(0xdeadbeef);
    const rng = prng.random();
    const gen = Sudoku.generate_solved_puzzle(rng);
    var puzzle = gen.puzzle;
    const ok = puzzle.solve();
    try std.testing.expect(ok);
    try std.testing.expect(puzzle.is_solved());
    try std.testing.expectEqualSlices(u8, &gen.solved.table, &puzzle.table);
}

test "generated puzzle should be solvable 2" {
    var prng = std.Random.DefaultPrng.init(0xdeadbeef);
    const rng = prng.random();
    const gen = generate_solved_puzzle_top(rng);
    const out = try solve(&gen.puzzle);
    try std.testing.expectEqualSlices(u8, &gen.solved, &out);
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
        try std.testing.expect(self.solve());
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
