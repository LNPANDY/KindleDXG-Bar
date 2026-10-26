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
