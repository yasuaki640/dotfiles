-- ============================================================
-- レビューの主役: git diff / PR レビュー / LSP 閲覧
-- ============================================================
return {
  -- gitsigns: 各行の追加/変更/削除を左端に表示、ハンク単位で diff を覗ける
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      on_attach = function(bufnr)
        local gs = require("gitsigns")
        local function map(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
        end
        map("n", "]h", gs.next_hunk, "次の変更ハンクへ")
        map("n", "[h", gs.prev_hunk, "前の変更ハンクへ")
        map("n", "<leader>hp", gs.preview_hunk, "ハンクの diff を覗く")
        map("n", "<leader>hb", function() gs.blame_line({ full = true }) end, "この行の blame")
        map("n", "<leader>tb", gs.toggle_current_line_blame, "行 blame の表示切替")
      end,
    },
  },

  -- diffview: git の差分を専用画面で一覧レビュー（ファイル間を移動しながら読める）
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<CR>", desc = "差分レビュー（working tree）" },
      { "<leader>gm", "<cmd>DiffviewOpen origin/main...HEAD<CR>", desc = "main との差分（ブランチ全体）" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<CR>", desc = "このファイルの変更履歴" },
      { "<leader>gH", "<cmd>DiffviewFileHistory<CR>", desc = "リポジトリ全体の履歴" },
      { "<leader>gx", "<cmd>DiffviewClose<CR>", desc = "差分ビューを閉じる" },
    },
    opts = {
      enhanced_diff_hl = true,
      view = {
        merge_tool = { layout = "diff3_mixed" },
      },
    },
  },

  -- octo: GitHub の PR / Issue を Neovim 内で閲覧・レビュー・コメント（gh 認証が必要）
  {
    "pwntester/octo.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    cmd = "Octo",
    keys = {
      { "<leader>op", "<cmd>Octo pr list<CR>", desc = "PR 一覧" },
      { "<leader>oo", "<cmd>Octo pr search<CR>", desc = "PR を検索" },
      { "<leader>oi", "<cmd>Octo issue list<CR>", desc = "Issue 一覧" },
      { "<leader>or", "<cmd>Octo review start<CR>", desc = "PR レビュー開始" },
    },
    opts = {
      use_local_fs = false,
      enable_builtin = true,
    },
  },

  -- lazygit を Neovim から起動（diff/ステージ/履歴を TUI で。ターミナル単体でも使える）
  {
    "kdheepak/lazygit.nvim",
    cmd = { "LazyGit", "LazyGitCurrentFile", "LazyGitFilter" },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>gg", "<cmd>LazyGit<CR>", desc = "lazygit を開く" },
    },
  },

  -- ----------------------------------------------------------------
  -- LSP（「読む」精度を上げる: 定義ジャンプ・参照・ホバー・診断）
  --   補完やフォーマッタは入れない（書かないので不要）
  -- ----------------------------------------------------------------
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      -- LSP サーバを GUI でインストール管理
      { "williamboman/mason.nvim", opts = {} },
      { "williamboman/mason-lspconfig.nvim" },
    },
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      -- バッファに LSP が付いたら閲覧系キーマップを張る
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local function map(keys, fn, desc)
            vim.keymap.set("n", keys, fn, { buffer = ev.buf, desc = desc })
          end
          map("gd", vim.lsp.buf.definition, "定義へジャンプ")
          map("gr", "<cmd>Telescope lsp_references<CR>", "参照を一覧")
          map("gi", vim.lsp.buf.implementation, "実装へジャンプ")
          map("gy", vim.lsp.buf.type_definition, "型定義へジャンプ")
          map("K", vim.lsp.buf.hover, "ホバー（型・ドキュメント）")
          map("<leader>ds", "<cmd>Telescope lsp_document_symbols<CR>", "ファイル内のシンボル")
          map("<leader>dd", vim.diagnostic.open_float, "この行の診断を表示")
          map("[d", function() vim.diagnostic.jump({ count = -1 }) end, "前の診断へ")
          map("]d", function() vim.diagnostic.jump({ count = 1 }) end, "次の診断へ")
        end,
      })

      -- mason 経由で入れた LSP を自動で有効化（手動で :Mason から足せる）
      require("mason-lspconfig").setup({
        -- よく読む言語をデフォルトで。不要なら削ってよい
        ensure_installed = { "lua_ls", "ts_ls", "jsonls", "yamlls" },
      })
    end,
  },
}
