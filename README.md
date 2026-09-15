# Kagami

<p align="center">
  <img src="Resources/KagamiIconSource.png" alt="Kagami 图标" width="112" />
</p>

> 用 AI 翻译单词或短语，确认后快速制成 Anki 卡片。

Kagami 的初衷很简单：把查词、整理释义、填写卡片和同步 Anki 这几步连成一条顺畅的流程，让制卡更轻松，把时间留给记忆本身。

![Kagami 主界面：输入单词、生成翻译并添加到 Anki](docs/images/main-window.svg)

## 能做什么

- **AI 翻译**：自动识别输入语言，生成简体中文释义；结果可直接手动修改。
- **本地或云端模型**：支持本地 [Ollama](https://ollama.com/) 模型，也支持 OpenAI Chat Completions 兼容的远程 API。
- **自动回退**：使用云端模型时，网络或请求失败可自动改用本地 Ollama。
- **按模板制卡**：读取 Anki 的卡组、笔记类型和字段名，按你的模板生成卡片内容与例句。
- **确认后同步**：预览并编辑各字段，确认后即可写入指定 Anki 卡组。

![Kagami 设置：模型来源与 AnkiConnect](docs/images/settings.png)

## 快速开始

**准备工作**

1. 使用 macOS 14 或更高版本。
2. 安装并打开 [Anki](https://apps.ankiweb.net/)，并安装 [AnkiConnect](https://ankiweb.net/shared/info/2055492159) 插件。
3. 选择一种模型来源：
   - 本地：安装并启动 Ollama，下载一个模型（推荐 `qwen3:8b`）。
   - 云端：准备一个 OpenAI Chat Completions 兼容 API 的地址、模型名和密钥（实测本地小模型效果不太好，最好还是用聪明的的模型，翻译也用不了多少token）。

**使用步骤**

1. 打开 Kagami，在「设置」中读取本地模型，或填写云端 API 信息。
2. 点击「连接并刷新」，选择默认 Anki 卡组和笔记类型，再刷新字段。
3. 在主界面输入单词或短语，点击「生成翻译」。
4. 检查或修改翻译，点击「添加到 Anki」。
5. 预览卡片字段，确认后写入 Anki。

## 从源码运行

```bash
./script/build_and_run.sh
```

Kagami 会将云端 API 密钥保存在 macOS 钥匙串中；Anki 数据始终由本机的 AnkiConnect 写入。
