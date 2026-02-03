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
  const app = document.querySelector(selector)
  app.innerHTML = `
    <div id="sudoku-grid" class="font-mono font-bold text-slate-700 grid grid-cols-9 grid-rows-9 w-fit gap-0.5 mx-auto mt-12"></div>
    <div class="flex mx-auto justify-center gap-1.5 mt-6 font-mono">
      <button id='sudoku-random' type="button" class="cursor-pointer bg-slate-600 text-white rounded-md px-4 py-2 w-30 shadow">random</button>
      <button id='sudoku-solve' type="button" class="cursor-pointer bg-slate-600 text-white rounded-md px-4 py-2 w-30 shadow">solve</button>
      <a href="https://github.com/krist7599555/sudoku-zig" class="text-center cursor-pointer bg-slate-600 text-white rounded-md px-4 py-2 w-30 shadow">github</a>
    </div>
  `
  const grid = document.getElementById("sudoku-grid");

  function render() {
    grid.innerHTML = app.dataset.sudoku
      .split("")
      .map((c, i) => {
        const box = Math.floor(i / 27) * 3 + Math.floor((i % 9) / 3);
        const val = c.replace(".", "");
        return `
            <div
              data-idx='${i}'
              data-box='${box}'
              class="size-10 p-2 text-center border border-slate-200 shadow-md ${[1,3,5,7].includes(box) ? 'bg-slate-300' : 'bg-slate-50'}"
            >${val}</div>`;
      })
      .join("");

    for (const cell of grid.children) {
      const idx = parseInt(cell.dataset.idx);
      if (isNaN(idx)) continue;
      cell.addEventListener("click", () => handleClickCell(idx))
    }
  } // end-render

  function replaceAt(str, index, char) {
    return str.slice(0, index) + char + str.slice(index + 1);
  }
  function handleClickCell(idx) {
    let newVal = app.dataset.sudoku[idx]; // newVal = oldVal
    if (newVal == '.') {
      const num = parseInt(prompt("input number"))
      if (!isNaN(num) && 0 < num && num <= 9) {
        newVal = `${num}`;
      }
    } else {
      newVal = '.';
    }
    setBoard(replaceAt(app.dataset.sudoku, idx, newVal));
    render()
  }

  function setBoard(str) {
    app.dataset.sudoku = str;
    render();
  }

  function random() {
    setBoard(SudokuWasm.generate_solved_puzzle().puzzle);
  }

  function solve() {
    let out;
    try {
      out = SudokuWasm.solve(app.dataset.sudoku)
      setBoard(out);
    } catch(err) {
      alert("CAN NOT BE SOLVE")
    }
  }

  document.getElementById('sudoku-random').addEventListener("click", random)
  document.getElementById('sudoku-solve').addEventListener("click", solve)
 
  random();

  return {
    random,
    solve,
    setBoard,
  }
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
      as_str() {
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
    const res = out.as_str();
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
      solved: out_solved.as_str(),
      puzzle: out_puzzle.as_str(),
    };
    free_all_memory();
    return res;
  }

  return {
    solve,
    generate_solved_puzzle,
  };
}