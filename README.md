# gen-unreleased.sh

A bash script to automatically generate an "## Unreleased changes" section for your `CHANGELOG.md` using an LLM.

## Usage

```bash
./gen-unreleased.sh
```

## Requirements

- `git`
- [`llm`](https://github.com/simonw/llm) CLI tool
- [`repo2prompt`](https://crates.io/crates/repo2prompt) CLI tool

The script will use the LLM model specified by the `LLM_MODEL` environment variable (defaulting to `venice/deepseek-r1-671b`) and will update or create a `CHANGELOG.md` file in the current directory.