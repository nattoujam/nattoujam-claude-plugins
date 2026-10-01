# nattoujam-claude-plugins

自作の [Claude Code](https://code.claude.com) skill / plugin を配布する個人用マーケットプレイスです。

## セットアップ

```
/plugin marketplace add https://github.com/nattoujam/nattoujam-claude-plugins
/plugin install doc-guard@nattoujam-claude-plugins
```

hook や output style を含むプラグイン（`doc-guard` / `shell-guard` / `mopu`）は、インストール後に Claude Code を再起動すると有効になります。

## 収録プラグイン

- `doc-guard` — コメントや .md の段落を追加すると差し戻す hook。コメントと文書の追加・変更をレビューし、不要な記述を差し戻す。`~/.claude/` 配下、scratchpad、`/tmp` は検査しません。CLAUDE.md・SKILL.md・サブエージェント定義など読み手が Claude の文書は、指示の理由を書いてよい別の基準で判定します。README.md を同じ基準で書く/レビューする/分割するスキル `readme-policy` を含みます
- `shell-guard` — 使い捨ての `python - <<EOF` を Bash で実行しようとすると止める hook。コマンドの先頭行に `# 理由: …` があれば通します
- `mopu` — 語尾「〜モプ」で数字を並べて押し通すキャラクター「モプ」の output style。`/output-style` で選びます

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
