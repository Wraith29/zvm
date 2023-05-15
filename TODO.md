# TODO

* [ ] Add Linux Support
* [ ] Auto-Add `ZIG_PATH` to Environment Variables, and add `ZIG_PATH` to PATH
* [x] Better Error Handling
  * Stuff like:
  * [x] Exit early on trying to install existing version
  * [x] If Paths exist, don't error trying to create them
* [ ] More Options
  * [ ] Select -> Allow the user to select from installed versions
  * [ ] Delete -> Allow the user to delete an installed version
  * [ ] Latest -> Allow the user to install latest master build
    * ^ Will require deleting current master before re-installing
  * [ ] Current -> Write Current selected version to stdout
* [ ] Remove `7z` dependency
  * Options:
  * [ ] Implement own zip decompressor
  * [ ] Bundle `7z` exe with release?
  * [ ] Add a Zig package with zip decompression
* [x] Improve Arg Parser
  * [x] Interpret first non flag as command, rest as parameters
  * [x] Provide list of valid commands
* [ ] Add Custom Logging
  * Would be nice to step away from the builtin logging for information
* [ ] Add More Extensive Testing
  * Add Tests for:
  * [ ] list
  * [ ] ArgParser
  * [ ] size? (maybe)
* [ ] Add Settings
* [ ] Fix any memory leaks
