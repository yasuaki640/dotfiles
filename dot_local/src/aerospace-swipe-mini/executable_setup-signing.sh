#!/usr/bin/env bash
# One-time setup: aerospace-swipe-mini を安定した自己署名コード署名 ID で署名できる
# ようにする。これにより、リビルドで中身 (cdhash) が変わっても TCC (Accessibility)
# は「同じ署名 ID = 同じアプリ」と判断し、付与した権限がリビルドをまたいで残る。
#
# ad-hoc 署名 (codesign --sign -) は同一性の証明にならず、ビルドごとに別アプリ扱い
# になって毎回 Accessibility を入れ直す羽目になる。安定した証明書で署名するとこれが
# 解消する (参考: 兄弟ツールの aerospace-swipe-mini / acsandmann 系の署名手法)。
#
# 使い方: 一度だけ  ./setup-signing.sh  を実行 → そのあと make / chezmoi のビルド
# フックが同じ ID で再署名する。証明書生成自体は冪等 (既にあれば何もしない)。
#
# この証明書生成は chezmoi の onchange フックには組み込まない。証明書は秘密鍵を含み
# keychain に入る環境固有の資産で、宣言的に再現すべきものではないため (各マシンで
# 一度だけ手動実行する)。ビルドフックは「証明書があれば使い、無ければ ad-hoc」で動く。
set -euo pipefail

CN="aerospace-swipe-mini"                         # 証明書のコモンネーム = 署名 identity
KC="$HOME/Library/Keychains/login.keychain-db"

# 既に同名の signing identity が login keychain にあれば何もしない (冪等)。
if security find-identity -p codesigning -v "$KC" 2>/dev/null | grep -q "$CN"; then
  echo "✓ signing identity '$CN' already present — nothing to do."
  exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# 1) 自己署名証明書 + 秘密鍵を作る。codesign 用に extendedKeyUsage=codeSigning を付与。
echo "[setup-signing] generating self-signed code-signing certificate '$CN'..."
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -subj "/CN=$CN" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# 2) 証明書と鍵を別々の PEM として login keychain に import する
#    (PKCS12 だと OpenSSL3 と macOS で "MAC verification failed" になることがあるため
#     分割 import で回避)。-T /usr/bin/codesign で codesign に鍵アクセスを許可。
security import "$tmp/cert.pem" -k "$KC" -T /usr/bin/codesign >/dev/null
security import "$tmp/key.pem"  -k "$KC" -T /usr/bin/codesign >/dev/null

# 3) コード署名用に証明書を信頼する。これが無いと自己署名は "invalid"
#    (CSSMERR_TP_NOT_TRUSTED) 扱いになり TCC が署名を尊重しない。GUI 認証が
#    出るので、ここでログインパスワードの入力を求められることがある。
echo "[setup-signing] trusting the certificate for code signing (may prompt for password)..."
if security add-trusted-cert -p codeSign "$tmp/cert.pem" >/dev/null 2>&1; then
  echo "✓ certificate trusted for code signing"
else
  echo "! trust step failed — run manually: security add-trusted-cert -p codeSign <cert>" >&2
fi

# 4) GUI プロンプト無しで codesign が鍵を使えるよう ACL を許可 (login keychain 対象)。
security set-key-partition-list -S apple-tool:,apple: -k "" "$KC" >/dev/null 2>&1 || true

echo "✓ done. Now rebuild (chezmoi apply / make) so the binary is signed with '$CN'."
echo "  After the first build, grant Accessibility once — it will then persist across rebuilds."
