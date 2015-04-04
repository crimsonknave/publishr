#!/bin/sh 
echo
echo "POSTPROCESSING"

outpath=$1

for file in `find ${outpath} -name *.html -o -name *.htm  -o -name *.php`
do
  sed -i \
      -e 's|title'"("'\([^'")"']*\)'")"'|<cite>\1</cite>|g' \
      -e 's|name'"("'\([^'")"']*\)'")"'|<var>\1</var>|g' \
      -e 's|\([FAQ]\):\s|<b>\1:<\/b> |g' \
      -e 's|\(\w\)\&rsquo;\(\w\)|\1\&#39;\2|g' \
      -e 's|'"("'\w'")"'|<i>&<\/i>|g' $file
  
  # copy img alt string below image
  perl -i -pe 's/alt="(.*?)"(.*?)\/>/alt= "\1" \2\/><br\/><code>\1<\/code><br\/>/' $file
  
  # widths must be entered without % or px, and will always be transformed into %
  perl -i -pe 's/width="(\d*?)"/width="\1%"/' $file
  
  # prettify footnotes
  sed -i -e 's|^\(<div class=.footnotes.>\)|<div class="outerline-top"></div>\1<h5>FOOTNOTES</h5>|g' $file
done

