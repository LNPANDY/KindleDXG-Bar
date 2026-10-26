# 字体下载

渲染器需要 Noto Sans CJK（思源黑体）两个字重，因体积原因（约 33 MB）不随仓库分发。
下载后放到本目录（`fonts/NotoSansCJKsc-Regular.otf` 与 `fonts/NotoSansCJKsc-Bold.otf`）。

一键下载：

```bash
cd fonts
curl -LO https://github.com/notofonts/noto-cjk/raw/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf
curl -LO https://github.com/notofonts/noto-cjk/raw/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Bold.otf
```

也可以在 `config.json` 里把 `font_regular` / `font_bold` 指向任意系统上可用的
TTF/OTF 路径（CJK 字体即可保证中文渲染）。

## 授权说明（可放心使用）

Noto Sans CJK（思源黑体）采用 **SIL Open Font License 1.1** 授权：

- ✅ 完全免费，可商用、可嵌入项目/固件/Release 再分发，无需支付任何费用
- ✅ 可自由修改、衍生（衍生字体需遵守 OFL，保留授权声明即可）
- 唯一要求：字体本身不能单独作为商品出售；随本项目（开源代码）分发完全合规

授权全文见 [OFL 1.1](https://openfontlicense.org/)，字体版权归 Google/Adobe 等贡献方所有。
