-- ============================================================
-- ファイル探索 / 全文検索 / ツリー閲覧
--   「どこに何があるか」を素早く辿るための道具
-- ============================================================
return {
  -- Telescope: ファイル名・全文（ripgrep）・バッファをあいまい検索
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      -- ネイティブ fzf でソートを高速化
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    cmd = "Telescope",
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "ファイルを探す" },
      { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "全文検索（grep）" },
      { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "開いてるバッファ" },
      { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "ヘルプ検索" },
      { "<leader>fr", "<cmd>Telescope oldfiles<CR>", desc = "最近開いたファイル" },
      { "<leader>fw", "<cmd>Telescope grep_string<CR>", desc = "カーソル下の語を検索" },
      { "<leader>fc", "<cmd>Telescope git_commits<CR>", desc = "コミット履歴を検索" },
    },
    config = function()
      local telescope = require("telescope")
      telescope.setup({
        defaults = {
          path_display = { "truncate" },
          -- .gitignore は尊重しつつ隠しファイルも対象に
          vimgrep_arguments = {
            "rg", "--color=never", "--no-heading", "--with-filename",
            "--line-number", "--column", "--smart-case",
          },
        },
        pickers = {
          find_files = { hidden = true },
        },
      })
      pcall(telescope.load_extension, "fzf")
    end,
  },

  -- ファイルツリー（左にディレクトリ構造を表示）
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    cmd = { "NvimTreeToggle", "NvimTreeFocus" },
    keys = {
      { "<leader>e", "<cmd>NvimTreeToggle<CR>", desc = "ファイルツリー開閉" },
    },
    opts = {
      view = { width = 36 },
      renderer = { group_empty = true },
      filters = { dotfiles = false }, -- 隠しファイルも表示
      git = { enable = true },        -- ツリー上に git 状態を色表示
    },
  },
}
