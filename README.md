# nattoujam-claude-plugins

自作の [Claude Code](https://code.claude.com) skill / plugin を配布する個人用マーケットプレイスです。

## セットアップ

```
/plugin marketplace add https://github.com/nattoujam/nattoujam-claude-plugins
/plugin install readme-policy@nattoujam-claude-plugins
/plugin install doc-guard@nattoujam-claude-plugins
```

hook を含むプラグイン（`doc-guard`）は、インストール後に Claude Code を再起動すると有効になります。

## 収録プラグイン

- `readme-policy` — README.md をポリシーに沿って書く/レビューする/分割する
- `doc-guard` — コメントや .md の段落を追加すると差し戻す hook。コメントは回答で候補として挙げるよう、段落は題目の確認を取ったかを問う。`~/.claude/` 配下、scratchpad、`/tmp` は検査しません

### doc-guard の検査対象から外す

.md 本文が成果物のリポジトリなど、検査が繰り返し誤検知するパスは、リポジトリ直下の `.doc-guard-ignore` に1行ずつ書くと外れます。`#` で始まる行はコメント、末尾の `/` と `**` はその配下すべてに一致します。

```
# 抽出結果そのものなので段落検査を外す
semantic/
docs/adr/**
CHANGELOG.md
```

プロジェクトの `.claude/settings.json` の env で `DOC_GUARD_EXCLUDE="docs/adr/**:wiki/**"` を渡す方法も使えます。

## 開発者向け

### 更新

インストールされたプラグインは、インストール時点のコミットのコピーです。このリポジトリを変更しても、以下を実行して再起動するまで各マシンには反映されません。

1. 変更したプラグインの `.claude-plugin/plugin.json` と `.claude-plugin/marketplace.json` の `version` を上げて push します
2. 各マシンで更新します

   ```
   claude plugin marketplace update nattoujam-claude-plugins
   claude plugin update <plugin>@nattoujam-claude-plugins
   ```

## ライセンス

MIT。[LICENSE](./LICENSE) を参照。
