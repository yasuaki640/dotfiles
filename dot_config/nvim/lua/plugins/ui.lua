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

  -- キーマップのヒントをポップアップ（Space を押すと次に押せるキーが出る）
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {},
  },
}
