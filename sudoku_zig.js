var SudokuWasm;

export async function init() {
  SudokuWasm ||= await loadSudokuZigWasm();
  window.SudokuWasm = SudokuWasm;
}

export function solve(str) {
  return SudokuWasm.solve(str)
}
export function generate_solved_puzzle(seed = Date.now()) {
  return SudokuWasm.generate_solved_puzzle(seed);
}

export function mount(selector) {
  const app = document.querySelector(selector);
  if (!app) throw new Error("mount: selector not found");

  const btn = `text-center cursor-pointer bg-slate-600 text-white rounded-md px-4 py-2 w-30 shadow`
  app.innerHTML = `
    <div id="sudoku-grid"
      class="font-mono font-bold text-slate-700 grid grid-cols-9 grid-rows-9 w-fit gap-0.5 mx-auto mt-12">
    </div>

    <div class="flex mx-auto justify-center gap-1.5 mt-6 font-mono">
      <button id='sudoku-random' type="button" class="${btn}">random</button>
      <button id='sudoku-solve' type="button" class="${btn}">solve</button>
      <a href="https://github.com/krist7599555/sudoku-zig" class="${btn}">github</a>
    </div>
  `;

  const grid = app.querySelector("#sudoku-grid");

  const replaceAt = (s, i, c) => s.slice(0, i) + c + s.slice(i + 1);
  const getBoard = () => app.dataset.sudoku;
  const setBoard = (str) => {
    app.dataset.sudoku = str;
    render();
  };
  const setBoardAt = (i, c) => {
    setBoard(replaceAt(getBoard(), i, c));
  }

  function render() {
    const board = getBoard();
    grid.innerHTML = board
      .split("")
      .map((c, i) => {
        const boxIndex = (i) => Math.floor(i / 27) * 3 + Math.floor((i % 9) / 3);
        const box = boxIndex(i);
        const isDarkBox = [1, 3, 5, 7].includes(box);
        return `
          <div
            data-idx="${i}"
            class="cursor-pointer size-10 p-2 text-center border border-slate-200 shadow-md
              ${isDarkBox ? "bg-slate-300" : "bg-slate-50"}">
            ${c === "." ? "" : c}
          </div>
        `;
      })
      .join("");
  }

  function handleCellClick(idx) {
    const cur = getBoard()[idx];
    let next = undefined;
    if (cur === ".") {
      const n = Number(prompt("input number (1-9)"));
      if (n >= 1 && n <= 9) next = String(n);
      else return;
    } else {
      next = '.'
    }
    setBoardAt(idx, next);
  }

  grid.addEventListener("click", (e) => {
    const cell = e.target.closest("[data-idx]");
    if (!cell) return;
    handleCellClick(Number(cell.dataset.idx));
  });

  const random = () =>
    setBoard(SudokuWasm.generate_solved_puzzle().puzzle);

  const solve = () => {
    try {
      setBoard(SudokuWasm.solve(getBoard()));
    } catch {
      alert("CAN NOT BE SOLVE");
    }
  };

  app.querySelector("#sudoku-random").onclick = random;
  app.querySelector("#sudoku-solve").onclick = solve;

  random();

  return { random, solve, setBoard };
}

async function loadSudokuZigWasm(url = "https://raw.githubusercontent.com/krist7599555/sudoku-zig/main/zig-out/bin/sudoku_zig.wasm") {
  // const res = await fetch("/zig-out/bin/sudoku_zig.wasm");
  const res = await fetch(url);
  const bytes = await res.arrayBuffer();
  const { instance, module } = await WebAssembly.instantiate(bytes, {});

  const wasm = instance.exports;
  const mem = new Uint8Array(wasm.memory.buffer);
  const encoder = new TextEncoder();
  let _molloc_end = 0;
  const molloc = (size) => {
    const res = _molloc_end;
    _molloc_end += size;
    return {
      addr: res,
      len: size,
      str() {
        return new TextDecoder().decode(mem.slice(res, this.addr + this.len));
      },
      write(s) {
        mem.set(encoder.encode(s.slice(0, this.len)), this.addr);
        return this;
      },
    };
  };
  const free_all_memory = () => (_molloc_end = 0);
  const exitcode = (status) => {
    if (status != 0) {
      throw new Error("wasm return error exit status = " + status);
    }
  };

  function solve(str) {
    if (str.length !== 81) throw new Error("input must be 81 bytes");
    const inp = molloc(81).write(str);
    const out = molloc(81);
    exitcode(wasm.abi_solve(inp.addr, out.addr));
    const res = out.str();
    free_all_memory();
    return res;
  }

  function generate_solved_puzzle(seed = Date.now()) {
    const out_solved = molloc(81);
    const out_puzzle = molloc(81);
    exitcode(
      wasm.abi_generate_solved_puzzle(
        BigInt(seed),
        out_solved.addr,
        out_puzzle.addr,
      ),
    );
    const res = {
      solved: out_solved.str(),
      puzzle: out_puzzle.str(),
    };
    free_all_memory();
    return res;
  }

  return {
    solve,
    generate_solved_puzzle,
  };
}