-- ============================================================
-- 見やすさ（カラースキーム / ステータスライン / シンタックス）
-- ============================================================
return {
  -- カラースキーム: tokyonight（diff の色分けが見やすい定番）
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000, -- 他より先に読み込む
    config = function()
      require("tokyonight").setup({ style = "moon" })
      vim.cmd.colorscheme("tokyonight")
    end,
  },

  -- ステータスライン（今いる場所・git ブランチが一目で分かる）
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    opts = {
      options = { theme = "tokyonight", globalstatus = true },
    },
  },

  -- シンタックスハイライト（読む精度に直結。閲覧主体なので重要）
  -- 安定版 master ブランチを使う（main ブランチは API 移行中のため固定）
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("nvim-treesitter.configs").setup({
        -- よく読む言語を最初から。足りなければ :TSInstall <lang> で追加
        ensure_installed = {
          "lua", "vim", "vimdoc", "bash",
          "javascript", "typescript", "tsx", "json", "yaml", "toml",
          "markdown", "markdown_inline", "html", "css",
          "python", "go", "rust", "dockerfile", "gitcommit", "diff",
        },
        highlight = { enable = true },
        indent = { enable = true },
        auto_install = true, -- 未対応言語のファイルを開いたら自動でパーサ取得
      })
    end,
  },

  -- バッファをタブとして画面上部に並べる（VSCode のタブ相当）
  --   Vim の tabpage は「ウィンドウ配置のセット」なので、ファイル1つ=タブ1つの
  --   VSCode 的な見え方はバッファをタブとして描く bufferline で得る。
  {
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    -- VimEnter で組む起動時レイアウト（init.lua）より前に読ませたいので遅延しない。
    -- 遅延すると offsets（nvim-tree の幅ぶんを空ける設定）が初回描画に間に合わない。
    lazy = false,
    keys = {
      { "<leader>bp", "<cmd>BufferLineTogglePin<CR>", desc = "タブをピン留め" },
      { "<leader>bo", "<cmd>BufferLineCloseOthers<CR>", desc = "他のタブを閉じる" },
    },
    opts = {
      options = {
        diagnostics = "nvim_lsp",       -- タブ上に LSP の警告・エラー数を出す
        show_buffer_close_icons = false, -- 閲覧主体なので × は不要
        separator_style = "slant",
        -- タブ列にはファイルだけを並べる。
        --   バッファリストは Neovim 全体で 1 本なので、右ペインのターミナルも
        --   放っておくと中央のファイルと同じ列に混ざる（`15635:/bin/zsh` 等）。
        --   ターミナル間の行き来はウィンドウ移動（Ctrl-h/l）でするため、
        --   タブ列からは除外して中央エディタの見通しを優先する。
        custom_filter = function(buf_number)
          return vim.bo[buf_number].buftype ~= "terminal"
        end,
        -- nvim-tree の幅ぶんはタブ列を空けて、ツリーの上に重ならないようにする
        offsets = {
          {
            filetype = "NvimTree",
            text = "Files",
            highlight = "Directory",
            separator = true,
          },
        },
      },
    },
  },

  -- キーマップのヒントをポップアップ（Space を押すと次に押せるキーが出る）
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {},
  },
}
