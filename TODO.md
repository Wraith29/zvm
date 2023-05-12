# TODO

* [ ] Add Linux Support
* [ ] Auto-Add `ZIG_PATH` to Environment Variables, and add `ZIG_PATH` to PATH
* [ ] Better Error Handling
  * Stuff like:
  * [ ] Exit early on trying to install existing version
  * [ ] If Paths exist, don't error trying to create them
* [ ] More Options
  * [ ] Select -> Allow the user to select from installed versions
  * [ ] Delete -> Allow the user to delete an installed version
  * [ ] Latest -> Allow the user to install latest master build
    * ^ Will require deleting current master before re-installing
* [ ] Remove `7z` dependency
  * Options:
  * [ ] Implement own zip decompressor
  * [ ] Bundle `7z` exe with release?
  * [ ] Add a Zig package with zip decompression
* [ ] Improve Arg Parser
  * [ ] Provide list of valid commands
