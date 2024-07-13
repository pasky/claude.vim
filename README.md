# Claude for AI Pair Programming in Vim / Neovim: Or, a Hacker's Gateway to LLMs

This vim plugin integrates Claude deeply into your Vim workflow - rather than
working in the clunky web Claude Chat, actually chat about and hack together
on your currently opened vim buffers.

This plugin is NOT for "code completion" like Github Copilot or Codeium.
(You can use these together with claude.vim!)
This plugin rather provides a chat / instruction centric interface.

**Claude is your pair programmer.**  You chat about what to build or how
to debug problems, and Claude offers opinions while seeing your actual code,
or goes ahead and proposes the modifications - high level, or just straight
writes the code.

This plugin will give you a partner who will one-shot new features in your codebase:

https://github.com/pasky/claude.vim/assets/18439/73ffcaac-d5b4-4508-b9fa-077c189d2c93

You can let it refactor your code if it's a bit messy, and have an ongoing discussion about it:

https://github.com/pasky/claude.vim/assets/18439/625060ca-600f-4774-adbe-ec93f94a30e9

You can ask it to modify or extend just a selected piece of your code:

https://github.com/pasky/claude.vim/assets/18439/71544b57-e87d-4dd4-a7e6-4051fa080d18

It can also (with your case-by-case consent) evaluate Python expression when figuring
out what you asked:

https://pbs.twimg.com/media/GSVCJ7pWsAA7Afs?format=png&name=4096x4096

Note that about 95% of the code of this plugin has been written by Claude
Sonnet 3.5, and most of the time already "self-hosted" within the plugin.

**NOTE: This is early alpha software.**  It is expected to rapidly evolve...
and not just in backwards compatible way.  Stay in touch with the maintainer
if you are using it (`pasky` on libera IRC, or @xpasky on Twitter / X, or just
via github issues or PRs).

## Installation

First, install using your favourite package manager, or use Vim's built-in package support.

Vim:

```
mkdir -p ~/.vim/pack/pasky/start
cd ~/.vim/pack/pasky/start
git clone https://github.com/pasky/claude.vim.git
```

Neovim:

```
mkdir -p ~/.config/nvim/pack/pasky/start
cd ~/.config/nvim/pack/pasky/start
git clone https://github.com/pasky/claude.vim.git
```

## Configuration

Obtain your Claude API key by signing up at https://console.anthropic.com/ .
Anthropic might give you a free $5 credit to get you started, which is plenty
for many hours of hacking (depending on your mode of usage).

**NOTE: This is a cloud service that costs actual money based on the amount
of tokens consumed and produced. Be careful when working with big content,
observe your usage / billing dashboard on Anthropic etc.**

Set your Claude API key in your .vimrc:

```vim
let g:claude_api_key = 'your_api_key_here'
```

(You can also use AWS Bedrock as your Claude provider instead - in that case, set `let g:claude_use_bedrock = 1` instead.)

## Usage

First, a couple of vim concepts you should be roughly familiar with:
- Switching between windows (`:help windows`) - at least `<C-W><C-W>` to cycle between active windows
- Diff mode (`:help diff`) - at least `d` `o` to accept the change under cursor
- Folds (`:help folding`) - at least `z` `o` to open a fold (chat interaction) and `z` `c` to close it
- Leader (`:help leader`) - if you are unsure, most likely `\` is the key to press whenever `<Leader>` is mentioned (but on new keyboards, `§` or `±` might be a nice leader to set)

Claude.vim currently offers two main interaction modes:
1. Simple implementation assistant
2. Chat interface

### ClaudeImplement

In this mode, you select a block of code and ask Claude to modify it in some
way; Claude proposes the change and lets you review and accept it.

1. Select code block in visual mode. (Note that this selection is all Claude
   "sees", with no additional context! Therefore, select liberally, e.g.
   a whole function.)
2. `<Leader>ci` - shortcut for `:'<,'>ClaudeImplement ...`
3. Enter your instruction (e.g. "Fix typos" or "Factor out common code" or "Add error handling" or "There's some bug here") as a ClaudeImplement parameter in the command mode
4. Review and accept proposed changes in diff mode
5. Switch to the scratch window (`<C-W>l`) and `:q` it.

### ClaudeChat

In this mode, you chat with Claude.  You can chat about anything, really,
but the twist is that Claude also sees the full content of all your buffers
(listed in `:buffers` - _roughly_ any files you currently have open in your vim).

1. `<Leader>cc` - shortcut for opening Claude chat window
2. Enter a message on the `You: ` line (and/or indented(!) below it)
3. `<C-]>` (in insert or normal mode) to send your message and get a reply
4. Read the reply in the Claude window etc.
5. If Claude proposes a code change, diff mode automatically pops up to apply it whenever possible.

You can e.g. ask Claude how to debug or fix a bug you observe, or ask it
to propose implementation of even fairly complex new functionality. For example:

    You: Can you write a short README.md for this plugin, please?
    Claude:
        Here's a draft README.md for the Claude Vim plugin:

        ```markdown
        # Claude Vim Plugin

        A Vim plugin for integrating Claude, an AI assistant, directly into your Vim workflow.
        ...

Previous interactions are automatically folded for easy orientation (Claude can
be a tad bit verbose), but the chat history is also visible to Claude when
asking it something.  However, you can simply edit the buffer to arbitrarily
redact the history (or just delete it).

**NOTE: For every single Claude Q&A roundtrip, full chat history and full
content of all buffers is sent.  This can consume tokens FAST.  (Even if it
is not too expensive, remember that Claude also imposes a total daily token
limit.) Prune your chat history regularly.**
