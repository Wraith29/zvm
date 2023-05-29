# Zig Version Manager

As of right now, this will only work on x86_64 Windows machines,
I am looking to improve this, but it will take a while.

## Usage

* list [-i]
  * lists installed versions of zig
* install \<version>
  * attempt to install the specified version
* latest
  * install latest version
* select \<version>
  * select the specified version (if installed)
* current
  * outputs current version in use

## Requirements

* `7z` executable on Path
* `pwsh` executable on Path
