# PublishR -- Rapid publishing for ebooks (epub, Kindle), paper (LaTeX) and the web (webgen)'
# Copyright (C) 2012 Red (E) Tools Ltd. (www.red-e.eu)
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
# 
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

module Publishr
  class Helper
    def self.strip_webgen_header_from_page_file(content)
      lines = content.split("\n").reverse
      stripped_content = []
      lines.each do |line|
        break if line.strip == '---'
        stripped_content << line
      end
      return stripped_content.reverse.join("\n")
    end
    
    def self.get_footnote_count_upto_file(inpath, language, filename)
      # inside of the whole publishr gem, @language must be prefixed with a dot
      language = language.include?('.') ? language : ".#{language}"
      
      total_footnote_count = 0
      total_citation_count = 0
      Dir[File.join(inpath,"*#{ language }.page")].sort.each do |f|
        break if File.basename(f) == filename
        footnotes_in_this_file = `grep -P '^\\[\\^.*?\\]\\:' #{ f } | wc -l`.to_i
        total_footnote_count += footnotes_in_this_file
        #Publishr.log "XXX footnotes_in_this_file #{ File.basename(f) } : #{ footnotes_in_this_file }"
        
        citations_in_this_file = `grep -o 'CITE' #{ f } | wc -l`.to_i
        total_citation_count += citations_in_this_file
        #Publishr.log "XXX citations_in_this_file #{ File.basename(f) } : #{ citations_in_this_file }"
      end
      #Publishr.log "XXX total_footnote_count #{ filename }: #{ total_footnote_count }\n\n"
      #Publishr.log "XXX total_citation_count #{ filename }: #{ total_citation_count }\n\n"
      return total_footnote_count, total_citation_count
    end
  
    def self.copy_images(inpath, outpath, language, filetype)
      # Copy all unlocalized images
      Dir[File.join(inpath,'images',"*.#{ filetype }")].each do |i|
        basename = File.basename(i)
        FileUtils.cp i, outpath if basename.count('.') == 1
      end
        
      # Copy all localized images, but only for the selected language
      Dir[File.join(inpath,'images',"*#{ language }.#{ filetype }")].each do |i|
        basename = File.basename(i)
        FileUtils.cp i, outpath
      end
    end
    
    def self.discover_all_used_and_available_citation_keys(inpath, language)
      bibliography_filename = File.join(inpath, "bibliography#{ language }.bib")

      unless File.exists?(bibliography_filename)
        return []
      end
      used_citation_keys = []
      Dir[File.join(inpath,"*#{ language}.page")].each do |file|
        contents = File.open(file, 'r').read
        used_citation_keys += contents.scan(/\[.*?\]{(.*?)}/)
      end

      used_citation_keys = used_citation_keys.flatten.uniq.sort
      bibliography_database = BibTeX.open(bibliography_filename)
      available_citation_keys = bibliography_database.to_a.collect{|i| i[:key] }
      used_and_available_citation_keys = used_citation_keys & available_citation_keys

      return used_and_available_citation_keys
    end
  end
end
    