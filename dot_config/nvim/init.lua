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
-- バッファ移動
map("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "前のバッファ" })
map("n", "<S-l>", "<cmd>bnext<CR>", { desc = "次のバッファ" })
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "バッファを閉じる" })
-- 保存・終了（たまに必要なとき用）
map("n", "<leader>w", "<cmd>write<CR>", { desc = "保存" })
map("n", "<leader>q", "<cmd>quit<CR>", { desc = "ウィンドウを閉じる" })

-- ----------------------------------------------------------------
-- ターミナル（:terminal を右分割で開いて使う）
-- ----------------------------------------------------------------
map("n", "<leader>tt", "<cmd>vsplit | terminal<CR>i", { desc = "右にターミナルを開く" })
map("t", "<Esc>", "<C-\\><C-n>", { desc = "ターミナルモード解除" })
-- Ctrl+hjkl はターミナルモード中はシェルの通常動作（Ctrl-h=1文字削除 等）に譲る。
-- Esc でノーマルモードに抜けた後は、58〜63行目のグローバルマップでウィンドウ移動できる。
-- ターミナルバッファでは行番号などが不要なので非表示に
vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = "no"
  end,
})

-- netrw は <C-l> に NetrwRefresh をバッファローカルで割り当てるため、
-- ウィンドウ移動の <C-l> が握りつぶされる。netrw バッファでだけ上書きする。
vim.api.nvim_create_autocmd("FileType", {
  pattern = "netrw",
  callback = function(args)
    vim.keymap.set("n", "<C-l>", "<C-w>l", { buffer = args.buf, desc = "右のウィンドウへ" })
  end,
})
