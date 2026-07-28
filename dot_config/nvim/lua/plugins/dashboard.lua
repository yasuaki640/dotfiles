-- ============================================================
-- スタート画面（snacks.nvim の dashboard）
--   claudecode.nvim の依存で既に入っている snacks を、
--   ダッシュボード用途にも明示的に設定する。
--   起動時レイアウトの組み立ては init.lua 側の VimEnter autocmd が行う。
-- ============================================================
return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    dashboard = {
      -- レイアウトは自前で組むので、snacks 側の自動オープンは切る
      -- （VimEnter で :lua Snacks.dashboard() を明示的に呼ぶ）
      enabled = true,
      preset = {
        keys = {
          { icon = " ", key = "f", desc = "ファイルを探す", action = ":Telescope find_files" },
          { icon = " ", key = "g", desc = "全文検索（grep）", action = ":Telescope live_grep" },
          { icon = " ", key = "r", desc = "最近開いたファイル", action = ":Telescope oldfiles" },
          { icon = " ", key = "d", desc = "差分レビュー", action = ":DiffviewOpen" },
          { icon = " ", key = "l", desc = "lazygit", action = ":LazyGit" },
          { icon = " ", key = "p", desc = "PR 一覧", action = ":Octo pr list" },
          { icon = " ", key = "c", desc = "nvim の設定", action = ":e ~/.config/nvim/init.lua" },
          { icon = " ", key = "L", desc = "Lazy（プラグイン管理）", action = ":Lazy" },
          { icon = " ", key = "q", desc = "終了", action = ":qa" },
        },
      },
      sections = {
        { section = "header" },
        { section = "keys", gap = 1, padding = 1 },
        { section = "startup" },
      },
    },
  },
}
