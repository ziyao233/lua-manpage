# lua-manpage

An ugly Lua script to convert Lua C API manual from Out Format documentation
to ROFF manpages.

Don't hesistate to press 'K' in VIM from now!

## Usage

- `mkman.lua` generates manpages.
- `mksite.sh` calls `mkman.lua`, renders HTML pages and generates an
  `index.html`

### mkman.lua

```
$ ./mkman.lua ~/Source/lua/manual/manual.of output
#	      <Source File>		    <Output Directory>
```

### mksite.sh

```
$ ./mksite.lua ~/Source/lua/manual/manual.of output
#	       <Source File>		     <Output directory>
```

## Requirements

- `mkman.lua` requires Lua 5.4.
- `mksite.sh` requires bash and mandoc. Only OpenBSD mandoc is tested, but it
  should work on other implementations as well.

## Example

A pack of HTML pages generated from Lua git repository is hosted on
[GitHub Pages](https://ziyao233.github.io/lua-manpage/).

## Limitations

- Extra spaces in generated manpages
- ~~Function/structure definitions with multiple lines may be rendered
  incorrectly.~~
- Check TODOs in `mkman.lua`!

## License

lua-manpage is distributed under Mozilla Public License version 2.0.

```
Copyright (c) 2024 Yao Zi.
```
