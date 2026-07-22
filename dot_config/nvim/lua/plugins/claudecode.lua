-- ============================================================
-- Claude Code 連携（coder/claudecode.nvim）
--   nvim から Claude Code CLI を起動し、IDE 連携（選択範囲送信・
--   diff レビュー・@ でのファイル/選択コンテキスト共有）を有効にする。
--   通信は WebSocket（Claude Code 公式 IDE プロトコル互換）。
-- ============================================================
return {
  "coder/claudecode.nvim",
  dependencies = { "folke/snacks.nvim" }, -- ターミナル UI 用（任意だが推奨）
  config = true,
  keys = {
    { "<leader>a", nil, desc = "AI/Claude Code" },
    { "<leader>ac", "<cmd>ClaudeCode<CR>", desc = "Claude Code 開閉" },
    { "<leader>af", "<cmd>ClaudeCodeFocus<CR>", desc = "Claude Code にフォーカス" },
    { "<leader>ar", "<cmd>ClaudeCode --resume<CR>", desc = "セッション再開" },
    { "<leader>aC", "<cmd>ClaudeCode --continue<CR>", desc = "直近の会話を継続" },
    { "<leader>am", "<cmd>ClaudeCodeSelectModel<CR>", desc = "モデル選択" },
    { "<leader>ab", "<cmd>ClaudeCodeAdd %<CR>", desc = "現在のバッファを送る" },
    -- ビジュアル選択を Claude へ送る
    { "<leader>as", "<cmd>ClaudeCodeSend<CR>", mode = "v", desc = "選択範囲を送る" },
    -- nvim-tree のファイルを送る（ツリーにフォーカス中）
    {
      "<leader>as",
      "<cmd>ClaudeCodeTreeAdd<CR>",
      desc = "ツリーのファイルを送る",
      ft = { "NvimTree", "neo-tree", "oil", "minifiles" },
    },
    -- Claude が提案した diff の承認 / 却下
    { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<CR>", desc = "diff を承認" },
    { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<CR>", desc = "diff を却下" },
  },
}
