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
- `doc-guard` — 追加したコメント行と .md の追加段落を「これがないと誰が何を間違えるか」で検査し、答えられないものを差し戻す hook。`~/.claude/` 配下、scratchpad、`/tmp` は検査しません

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
