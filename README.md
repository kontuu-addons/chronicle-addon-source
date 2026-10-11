# Chronicle: Voices of Azeroth

A lore journal and voiceover addon for WoW: Forever. Quest givers speak their lines out loud, each with a voice that suits them, and a journal keeps track of what you've done and tells it back to you as a story.

This repository has the addon's code. To play, download a release:

- [CurseForge](https://www.curseforge.com/wow/addons/chronicle-voices-of-azeroth) (with the voice packs, the CurseForge app installs them together)
- [Wago](https://addons.wago.io/addons/chronicle)
- [Releases](https://github.com/kontuu-addons/chronicle-addon-source/releases) here

Just the journal, without voices: [Chronicle: Story Journal](https://www.curseforge.com/wow/addons/chronicle-story-journal).

## Bugs and ideas

Open an issue here, or come by the [Chronicle Discord](https://discord.gg/NKevry7mY). If you can, include the quest or NPC, what you expected and what happened, and any Lua error (BugSack makes these easy to copy).

Small fixes are welcome as pull requests.

## What's here and what isn't

- The code: the .lua, .xml and .toc files, the translations and the icons.
- Not here: the story texts (`Data/Lore.lua` is a placeholder, the real one comes with every release) and the voice packs.

## For addon authors

Chronicle has a small API for other addons, through LibStub: `LibStub("Chronicle-1.0")`. It can play lines, tell which chapter a quest belongs to, give the words of a line and more. See `API.lua`.

## License

The code is free software under the GNU GPL v3, see `LICENSE`. The voices, the story texts and the artwork are All Rights Reserved, see `LICENSE-CONTENT.md`. Quest, NPC and book text from World of Warcraft belongs to Blizzard Entertainment. Chronicle is not affiliated with Blizzard Entertainment.
