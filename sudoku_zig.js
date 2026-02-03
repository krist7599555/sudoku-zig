var sudoku_wasm;

export async function init() {
  sudoku_wasm ||= await load_sudoku_zig_wasm();
  window.sudoku_wasm = sudoku_wasm;
}

export function solve(str) {
  return sudoku_wasm.solve(str)
}

export function generate_solved_puzzle(seed = Date.now()) {
  return sudoku_wasm.generate_solved_puzzle(seed);
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

  const replace_at = (s, i, c) => s.slice(0, i) + c + s.slice(i + 1);
  const get_board = () => app.dataset.sudoku;
  const set_board = (str) => {
    app.dataset.sudoku = str;
    render();
  };
  const set_board_at = (i, c) => {
    set_board(replace_at(get_board(), i, c));
  }

  function render() {
    const board = get_board();
    grid.innerHTML = board
      .split("")
      .map((c, i) => {
        const box_index_fn = (idx) => Math.floor(idx / 27) * 3 + Math.floor((idx % 9) / 3);
        const box_idx = box_index_fn(i);
        const is_dark_box = [1, 3, 5, 7].includes(box_idx);
        return `
          <div
            data-idx="${i}"
            class="cursor-pointer size-10 p-2 text-center border border-slate-200 shadow-md
              ${is_dark_box ? "bg-slate-300" : "bg-slate-50"}">
            ${c === "." ? "" : c}
          </div>
        `;
      })
      .join("");
  }

  function handle_cell_click(idx) {
    const cur = get_board()[idx];
    let next = undefined;
    if (cur === ".") {
      const n = Number(prompt("input number (1-9)"));
      if (n >= 1 && n <= 9) next = String(n);
      else return;
    } else {
      next = '.'
    }
    set_board_at(idx, next);
  }

  grid.addEventListener("click", (e) => {
    const cell = e.target.closest("[data-idx]");
    if (!cell) return;
    handle_cell_click(Number(cell.dataset.idx));
  });

  const random_fn = () =>
    set_board(sudoku_wasm.generate_solved_puzzle().puzzle);

  const solve_fn = () => {
    try {
      set_board(sudoku_wasm.solve(get_board()));
    } catch {
      alert("CAN NOT BE SOLVE");
    }
  };

  app.querySelector("#sudoku-random").onclick = random_fn;
  app.querySelector("#sudoku-solve").onclick = solve_fn;

  random_fn();

  return { random: random_fn, solve: solve_fn, set_board };
}

async function load_sudoku_zig_wasm(url = "https://raw.githubusercontent.com/krist7599555/sudoku-zig/main/zig-out/bin/sudoku_zig.wasm") {
  const res = await fetch(url);
  const bytes = await res.arrayBuffer();
  const { instance, module } = await WebAssembly.instantiate(bytes, {});

  const wasm = instance.exports;
  const mem = new Uint8Array(wasm.memory.buffer);
  const encoder = new TextEncoder();
  let malloc_end = 0;
  const malloc_fn = (size) => {
    const res_addr = malloc_end;
    malloc_end += size;
    return {
      addr: res_addr,
      len: size,
      str() {
        return new TextDecoder().decode(mem.slice(res_addr, res_addr + this.len));
      },
      write(s) {
        mem.set(encoder.encode(s.slice(0, this.len)), this.addr);
        return this;
      },
    };
  };
  const free_all_memory = () => (malloc_end = 0);
  const exit_code_check = (status) => {
    if (status != 0) {
      throw new Error("wasm return error exit status = " + status);
    }
  };

  function solve_wasm(str) {
    if (str.length !== 81) throw new Error("input must be 81 bytes");
    const inp = malloc_fn(81).write(str);
    const out = malloc_fn(81);
    exit_code_check(wasm.abi_solve(inp.addr, out.addr));
    const res_str = out.str();
    free_all_memory();
    return res_str;
  }

  function generate_solved_puzzle_wasm(seed = Date.now()) {
    const out_solved = malloc_fn(81);
    const out_puzzle = malloc_fn(81);
    exit_code_check(
      wasm.abi_generate_solved_puzzle(
        BigInt(seed),
        out_solved.addr,
        out_puzzle.addr,
      ),
    );
    const res_obj = {
      solved: out_solved.str(),
      puzzle: out_puzzle.str(),
    };
    free_all_memory();
    return res_obj;
  }

  return {
    solve: solve_wasm,
    generate_solved_puzzle: generate_solved_puzzle_wasm,
  };
}