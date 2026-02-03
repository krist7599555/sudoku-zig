const std = @import("std");
const solve_sudoku = @import("sudoku_zig").solve;
const Sudoku = @import("sudoku_zig").Sudoku;

pub fn main() !void {
    try test_basic();
    try test_pearly_6000(2);
    return;
}

fn test_basic() !void {
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const rng = prng.random();

    const sodoks = [_]Sudoku{
        Sudoku.generate_solved_puzzle(rng).puzzle,
        Sudoku.generate_solved_puzzle(rng).puzzle,
        try Sudoku.from_string("7...2654..98.75.2...5.4.97198.6.275.....87.1934.5....26592..4...34.6..85..235.1.."),
        try Sudoku.from_string("000000009002004700100000080000302006003007500600005000090040001006700200800000060"),
        try Sudoku.from_string("300000700010009005004000020000502000000048001080960000200000040007000300090050008"),
        // AI-Generated Hardest List: A frequently cited set of 11,000+ extremely hard puzzles found by researchers, often starting with puzzles like
        try Sudoku.from_string("4.....8.5.3..........7......2.....6.....8.4......1.......6.3.7.5..2.....1.4......"),
        // #3) AI Escagot 2006 {Se 10.4} { solved this one one here needs an AA MSLS }
        try Sudoku.from_string("100007090030020008009600500005300900010080002600004000300000010040000007007000300"),
        // #2) AI Everest 2010: SE 10.6 https://www.reddit.com/r/sudoku/comments/12bbt5z/deleted_by_user/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
        try Sudoku.from_string("800000000003600000070090200050007000000045700000100030001000068008500010090000400"),
        // #1) AI Etana (2010): se 10.6
        try Sudoku.from_string("005300000800000020070010500400005300010070006003200080060500009004000030000009700"),
        // rated SE 11.6 (Escargot is 10.7 for comparison)
        try Sudoku.from_string("500000009020100070008000300040002000000050000000706010003000800060004020900000005"),
        // Golden Nugget
        try Sudoku.from_string("000000039000010005003005800008009006070020000100400000009008050020000600400700000"),
    };
    for (sodoks, 0..) |_, i| {
        var puzzle = sodoks[i];
        var solved = puzzle; // clone
        const solvable = solved.inplace_solve();
        std.debug.assert(solvable);
        std.debug.print("\nQUESTION: {}\n", .{i});
        std.debug.print("inp: [{s}]\n{s}\n", .{ puzzle.to_string(), puzzle.pretty_string() });
        std.debug.print("out: [{s}]\n{s}\n", .{ solved.to_string(), solved.pretty_string() });
    }
}

fn test_pearly_6000(n: usize) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const data = try std.fs.cwd().readFileAlloc(
        allocator,
        "./src/pearly6000.txt",
        1000000,
    );
    defer allocator.free(data);

    var it = std.mem.splitScalar(u8, data, '\n');
    var i: u16 = 1;
    std.debug.print("\n# TEST pearly6000.txt [0..{}]\n\n", .{n});
    while (it.next()) |line| {
        std.debug.print("line = '{}'\n", .{i});
        const table_str = line[0..81];
        std.debug.print("puzz = '{s}'\n", .{table_str});
        var timer = try std.time.Timer.start();
        const t2 = try solve_sudoku(table_str);
        const ns = timer.read();
        std.debug.print("solv = '{s}'\n", .{t2});
        std.debug.print("time = '{:.3} ms'\n", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
        std.debug.print("\n", .{});
        i += 1;
        if (i > n) break;
    }
}
