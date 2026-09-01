-- ============================================================
-- レビュー特化 Neovim 設定
--   用途: ソース閲覧 / git diff / PR レビュー（書くのは AI に任せる）
--   構成: 素の Neovim + 厳選プラグイン（lazy.nvim 管理）
-- ============================================================

-- リーダーキーは Space（プラグイン読込より前に設定する必要がある）
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ----------------------------------------------------------------
-- 基本オプション（読む・見るに最適化）
-- ----------------------------------------------------------------
local opt = vim.opt
opt.number = true              -- 行番号
opt.relativenumber = true      -- 相対行番号（j/k 移動がしやすい）
opt.cursorline = true          -- カーソル行をハイライト
opt.wrap = false               -- 折り返さない（diff が読みやすい）
opt.scrolloff = 8              -- 上下8行は常に見える
opt.signcolumn = "yes"         -- 左の符号列を常に表示（gitsigns 用）
opt.termguicolors = true       -- True Color（カラースキームに必須）
opt.mouse = "a"                -- マウスも使える（スクロール等）
opt.clipboard = "unnamedplus"  -- システムクリップボード連携
opt.ignorecase = true          -- 検索は基本大小無視
opt.smartcase = true           -- 大文字を含むときだけ区別
opt.splitright = true          -- 縦分割は右に
opt.splitbelow = true          -- 横分割は下に
opt.updatetime = 250           -- 反応を速く（gitsigns/LSP 表示）
opt.timeoutlen = 400           -- キーマップ待ち時間
opt.undofile = true            -- アンドゥ履歴を永続化
opt.swapfile = false           -- スワップは作らない（閲覧主体なので不要）

-- ----------------------------------------------------------------
-- lazy.nvim ブートストラップ
-- ----------------------------------------------------------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ----------------------------------------------------------------
-- プラグイン読込（lua/plugins/ 配下を全部読む）
-- ----------------------------------------------------------------
require("lazy").setup("plugins", {
  change_detection = { notify = false },
})

-- ----------------------------------------------------------------
-- グローバルなキーマップ（プラグイン固有のものは各ファイル側）
-- ----------------------------------------------------------------
local map = vim.keymap.set
-- 検索ハイライトを消す
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "検索ハイライト解除" })
-- ウィンドウ移動（Ctrl + hjkl）
map("n", "<C-h>", "<C-w>h", { desc = "左のウィンドウへ" })
map("n", "<C-j>", "<C-w>j", { desc = "下のウィンドウへ" })
map("n", "<C-k>", "<C-w>k", { desc = "上のウィンドウへ" })
map("n", "<C-l>", "<C-w>l", { desc = "右のウィンドウへ" })
-- ウィンドウリサイズモード（<leader>wr で入り、hjkl で連続調整、それ以外のキーで抜ける）
local function resize_mode()
  vim.notify("Resize mode: h/j/k/l で調整、他のキーで終了", vim.log.levels.INFO)
  while true do
    local ok, key = pcall(vim.fn.getcharstr)
    if not ok then break end
    if key == "h" then vim.cmd("vertical resize -3")
    elseif key == "l" then vim.cmd("vertical resize +3")
    elseif key == "k" then vim.cmd("resize +2")
    elseif key == "j" then vim.cmd("resize -2")
    else break end
    vim.cmd("redraw")
  end
end
map("n", "<leader>wr", resize_mode, { desc = "ウィンドウリサイズモード" })
-- バッファ移動（bufferline のタブ表示と順序を揃えるため BufferLineCycle を使う）
map("n", "<S-h>", "<cmd>BufferLineCyclePrev<CR>", { desc = "前のバッファ" })
map("n", "<S-l>", "<cmd>BufferLineCycleNext<CR>", { desc = "次のバッファ" })
-- タブの位置を入れ替える
map("n", "<leader>b<", "<cmd>BufferLineMovePrev<CR>", { desc = "タブを左へ移動" })
map("n", "<leader>b>", "<cmd>BufferLineMoveNext<CR>", { desc = "タブを右へ移動" })
-- <leader>1〜9 で n 番目のタブへ直接ジャンプ
for i = 1, 9 do
  map("n", "<leader>" .. i, "<cmd>BufferLineGoToBuffer " .. i .. "<CR>",
    { desc = i .. " 番目のタブへ" })
end
-- バッファを閉じる。素の :bdelete はそのウィンドウごと閉じて分割レイアウトを
-- 壊すので、先に隣のバッファへ逃がしてから元のバッファだけを消す。
map("n", "<leader>bd", function()
  local buf = vim.api.nvim_get_current_buf()
  vim.cmd("BufferLineCycleNext")
  -- 他にバッファが無ければ切り替わらない。その場合は空バッファを用意する
  if vim.api.nvim_get_current_buf() == buf then vim.cmd("enew") end
  pcall(vim.api.nvim_buf_delete, buf, {})
end, { desc = "バッファを閉じる（レイアウト維持）" })
-- 保存・終了（たまに必要なとき用）
map("n", "<leader>w", "<cmd>write<CR>", { desc = "保存" })
map("n", "<leader>q", "<cmd>quit<CR>", { desc = "ウィンドウを閉じる" })

-- ----------------------------------------------------------------
-- ターミナル（:terminal を右分割で開いて使う）
-- ----------------------------------------------------------------
map("n", "<leader>tt", "<cmd>vsplit | terminal<CR>i", { desc = "右にターミナルを開く" })
map("t", "<C-t>", "<C-\\><C-n>", { desc = "ターミナルモード解除" })
-- Esc はターミナルジョブ（Claude Code など）にそのまま渡すため、あえてマップしない。
-- Ctrl+hjkl はターミナルモード中はシェルの通常動作（Ctrl-h=1文字削除 等）に譲る。
-- Ctrl-t でノーマルモードに抜けた後は、58〜63行目のグローバルマップでウィンドウ移動できる。
-- ターミナルバッファでは行番号などが不要なので非表示に
vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = "no"
  end,
})

-- ----------------------------------------------------------------
-- 起動時レイアウト（`nvim .` のようにディレクトリを開いたときだけ）
--   左: nvim-tree / 中央: snacks ダッシュボード / 右: terminal
--   ファイルを直接開いたとき（`nvim foo.lua`）や stdin 経由では組まない。
-- ----------------------------------------------------------------
local function open_ide_layout(dir)
  -- ディレクトリバッファ（netrw）を捨てて、中央を空バッファにする
  local dirbuf = vim.api.nvim_get_current_buf()
  vim.cmd("enew")
  pcall(vim.api.nvim_buf_delete, dirbuf, { force = true })

  -- カレントディレクトリを開いた先に合わせる（Telescope/lazygit の起点になる）
  vim.cmd.cd(dir)

  -- 右にターミナル。幅は全体の 1/3 程度
  vim.cmd("botright vsplit | terminal")
  vim.api.nvim_win_set_width(0, math.floor(vim.o.columns / 3))
  local termwin = vim.api.nvim_get_current_win()

  -- 左にファイルツリー
  -- nvim-tree は遅延ロード指定なので、VimEnter 時点ではコマンドが未定義。
  -- 先に lazy へロードを促してから API 経由で開く。
  require("lazy").load({ plugins = { "nvim-tree.lua" } })
  require("nvim-tree.api").tree.open()

  -- 中央のウィンドウを特定して、そこにダッシュボードを描画する。
  -- win を渡さないと snacks は画面全体を覆うフローティングを作り、
  -- 左のツリーと右のターミナルが隠れてしまう。
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
    if win ~= termwin and ft ~= "NvimTree" then
      vim.api.nvim_set_current_win(win)
      require("snacks").dashboard({ win = win })
      break
    end
  end
end

vim.api.nvim_create_autocmd("VimEnter", {
  nested = true, -- NvimTreeOpen 等が発火する autocmd を殺さない
  callback = function()
    -- 引数がちょうど 1 つで、それがディレクトリのときだけ
    if vim.fn.argc() ~= 1 then return end
    local arg = vim.fn.argv(0)
    if vim.fn.isdirectory(arg) == 0 then return end
    -- stdin から読んでいる場合（`cat x | nvim -`）は対象外
    if vim.g.__stdin_read then return end
    open_ide_layout(vim.fn.fnamemodify(arg, ":p"))
  end,
})

vim.api.nvim_create_autocmd("StdinReadPre", {
  callback = function() vim.g.__stdin_read = true end,
})

-- netrw は <C-l> に NetrwRefresh をバッファローカルで割り当てるため、
-- ウィンドウ移動の <C-l> が握りつぶされる。netrw バッファでだけ上書きする。
vim.api.nvim_create_autocmd("FileType", {
  pattern = "netrw",
  callback = function(args)
    vim.keymap.set("n", "<C-l>", "<C-w>l", { buffer = args.buf, desc = "右のウィンドウへ" })
  end,
})
