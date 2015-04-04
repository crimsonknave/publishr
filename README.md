PublishR
=================

This is a rapid publishing processor for ebooks (MOBI format for Amazon Kindle, EPUB format for other ebook readers), for real books (PDF through LaTeX) and the web (static webpages through `webgen`).

This processor harnesses the publishing powers of `LaTeX`, `kramdown` and `webgen` and adds proven ebook compilation algorithms to the mix.

PublishR is a command line publishing platform allowing users to efficiently render a content source into several different output formats.

The author of this Gem, Red (E) Toold Ltd., provides a [convenient web-based frontend](http://red-e.eu/app/publishr) for it (also named Publishr), adding the version management and collaboration powers of `git` to the mix.

All output formats are generated only from *one* well structured file system consisting of plain-text `kramdown` files, images, and configuration files, thereby saving any conversion work between output formats. Further, since there is only one text-based source, changes to this text propagate directly to all output formats, thereby saving work on keeping many formats up-to-date.

With PublishR you can handle voluminous books with the same ease as short articles. PublishR uses one of the world's best typesetting programs, LaTeX, as a backend for generating PDFs.

For ebooks, it uses its own algorithms for generating optimized Kindle HTML code, a cover page, copyright page, title page, table of contents, footnotes and Kindle-optimized navigation, all wrapped into one MOBI file with Amazon's proprietary converter, which is not part of this package due to licensing reasons and must be downloaded from the Amazon website.

Static webpages are generated with help of the `webgen` gem.

PublishR (like LaTeX) is based on the idea that authors should be able to focus on the content of what they are writing without being distracted by its visual presentation. In preparing a PublishR document, the author specifies the logical structure using familiar concepts such as chapter, headings, quotes, footnotes, images, etc. (utilizing [kramdown](http://kramdown.rubyforge.org/) markup) and lets the publishing system worry about the presentation of these structures. It therefore encourages the separation of layout from content while still allowing manual typesetting adjustments where needed.

Usage
----------

`gem install publishr`

For PDF generation, you also need to install LaTeX:

`apt-get install texlive-full`

You have to prepare a required "source directory". As a starting point, clone the example source directory from https://github.com/michaelfranzl/PublishR/tree/master/lib/document_skeleton. If you point PublishR to this directory, it will produce all output formats successfully.

The command line syntax is

`publishr source_path output_format language [path_to_mobi_converter]`

For example

`publishr ~/Documents/my_project/src ebook en ~/Downloads/converters`

where:

`source_path`: (mandatory) This is the path to the source directory (see above). For the formats `pdf` and `ebook` you have to include the subdirectory `/src` in the path. For the format `web` do not append `/src`.

`format`: (mandatory) This specifies the ouput format you want to generate. Valid options are `ebook`, `pdf` and `web`.

`language`: (mandatory) Specifies an arbitrary language string. In `source_path` only those `.page` files will be considered which have `language` in their file name. For a quick test, use `en` with the document example hosted at https://github.com/michaelfranzl/PublishR/tree/master/lib/document_skeleton

`converters_path`: (optional). This is the path which must contain Amazon's propritary binary `kindlegen`, which Amazon provides for free at the time of this writing. If this program is not present, an `epub` file is still generated but no Kindle `mobi` is generated.
  

Output file naming scheme
------------------

The output files are as follows, depending on the `format` attribute. The output directory is `source_path`.

`ebook`
: `unnamed.{language}.epub` and `unnamed.{language}.mobi`

`pdf`
: `unnamed.{language}.pdf`

`web`
: A directory named `out` will be generated as a sibling to the `src` directory. Please refer to the documentation of the Ruby library `webgen` to understand this more fully.


Full documentation
--------------------------

The features of this Gem and the source directory structure are fully documented at [http://documentation.red-e.eu/publishr](http://documentation.red-e.eu/publishr), even though this documentation describes our user-friendly web-based frontend for this Gem (see [http://red-e.eu/app/publishr](http://red-e.eu/app/publishr) for more information).


License
-------

PublishR -- Rapid publishing for ebooks (epub, Kindle), paper (LaTeX) and the web (webgen)'
Copyright (C) 2012 Red (E) Tools Ltd. (www.red-e.eu)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.