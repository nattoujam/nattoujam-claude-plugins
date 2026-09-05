# nattoujam-claude-plugins

自作の [Claude Code](https://code.claude.com) skill / plugin を配布する個人用マーケットプレイスです。

## セットアップ

```
/plugin marketplace add nattoujam/nattoujam-claude-plugins
```

## 使い方

```
/plugin install readme-policy@nattoujam-claude-plugins
```

複数マシンで使い回す場合は、各マシンの `~/.claude/settings.json` に以下を追加すると、フォルダを信頼した時点で自動的にマーケットプレイスが登録されます。

```json
{
  "extraKnownMarketplaces": {
    "nattoujam-claude-plugins": {
      "source": {
        "source": "github",
        "repo": "nattoujam/nattoujam-claude-plugins"
      }
    }
  },
  "enabledPlugins": {
    "readme-policy@nattoujam-claude-plugins": true
  }
}
```

## 収録プラグイン

- `readme-policy` — README.md をポリシーに沿って書く/レビューする/分割する

## ライセンス

MIT。[LICENSE](./LICENSE) を参照。
