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
  
  # this class is mainly responsible for transforming Publishr's superset of kramdown into pure kramdown (see preprocessing method), most notably the CITE syntax and special comments (pagebreak). It is actually a preprocessor for the HtmlProcessor class. It is used by publishr_web for its preview window and by the EbookRenderer class of this module.
  class KramdownProcessor

    def initialize(inpath, metadata={}, language=nil, image_url_prefix='')
      @line = ""
      @inpath = inpath
      @image_url_prefix = image_url_prefix
      
      # set language
      # inside of the whole publishr gem, @language must be prefixed with a dot
      if language and not language.empty?
        @language = language.include?('.') ? language : ".#{language}" 
      else
        @language = nil
      end
      
      # set metadata
      @metadata = metadata
      metadata_path = File.join(@inpath,"metadata#{@language}.yml")
      if File.exists?(metadata_path)
        @metadata ||= YAML::load(File.open(metadata_path, 'r').read)
      end
      
      # user-defined content filtering
      filter_filepath = File.join(@inpath,"filter#{ @language }.js")
      if File.exists?(filter_filepath)
        @v8_context = V8::Context.new
        filter_code = "(function() { var filters = {};"
        filter_code += File.read(filter_filepath)
        filter_code += "\nreturn filters;})()"
        @v8_object = @v8_context.eval(filter_code)
      end

      # initialize bibliography variables
      bibliography_database_filename = File.join(@inpath, "bibliography#{ @language }.bib")
      if File.exists?(bibliography_database_filename)
        @bibliography_database = BibTeX.open(bibliography_database_filename)
      else
        @bibliography_database = nil
      end
      @used_and_available_citation_keys = Helper.discover_all_used_and_available_citation_keys(@inpath, @language)
      @bibliography_footnotes = []
    end
    
    # getter
    def bibliography_database
      @bibliography_database
    end
    
    # getter
    def used_and_available_citation_keys
      @used_and_available_citation_keys
    end

    def transform_superset(kramdown, filename)
      processed_lines = []
      lines = kramdown.split("\n")
      lines.each do |line|
        @line = line
        
        # strip lines with only spaces. this is a common user error which causes kramdown to interpret it as line breaks
        @line.gsub!(/^\s*$/, '')
        
        # approximate Koma Script's part formatting for ebook readers. the part title will be displayed on a separate page, then a page break follows. the syntax is a special comment like
        # {::comment}\\part{This is part one of the book}{:\/}
        @line.gsub!(/{::comment}\\part{(.*?)}{:\/}/) {"<br /><br /><br /><br />\n\n# #{ $1 }\n\n{::comment}\pagebreak{:/}\n"}
        
        # transform the special comment "pagebreak" into html (kramdown can parse plain html and outputs it verbosely)
        @line.gsub!('{::comment}\pagebreak{:/}', "<br style='page-break-before:always;'>")
        
        set_citations
        processed_lines << @line
      end
      
      processed_lines =
          processed_lines.join("\n") +
          "\n\n" +
          @bibliography_footnotes.join("\n")

      if @v8_object
        processed_lines = run_custom_filter(processed_lines, filename)
      end

      return processed_lines
    end
    
    def convert_from_html(html)
      kramdown = Kramdown::Document.new(html, :input => 'html', :line_width => 100000 ).to_kramdown
      kramdown.gsub!(/\!\[(.*?)\]\((.*?)\)/){ "![#{$1}](#{@image_url_prefix}#{$2})" }
      kramdown.gsub! '\"', '"'
      kramdown.gsub! "\\'", "'"
      kramdown.gsub! "\\[", "["
      kramdown.gsub! "\\]", "]"
      return kramdown
    end
    
    private

    # this method formats citations similar to biblatex
    
    def set_citations
      if @line.include?("CITE") # speed improvement
        
        # for the bibtex syntax \cite[prenote][postnote]{bibkey} (single source with prenote)
        rx_cite_prenote_postnote = /CITE\[([^\]]*?)\]\[(.*?)\]\{(\w+)\}/
        @line.gsub!(rx_cite_prenote_postnote) do |string|
          matches  = rx_cite_prenote_postnote.match(string)
          prenote  = matches[1]
          postnote = matches[2]
          bibkey   = matches[3]
          entryarray = [format_citation_entry(bibkey, postnote, prenote)]
          format_citation(entryarray)
        end
        
        # for the bibtex syntax \cite[postnote]{bibkey} (single source without prenote)
        rx_cite_postnote = /CITE\[(.*?)\]{(\w+?)}/
        @line.gsub!(rx_cite_postnote) do |string|
          matches = rx_cite_postnote.match(string)
          prenote = nil
          postnote = matches[1]
          bibkey = matches[2]
          entryarray = [format_citation_entry(bibkey, postnote, prenote)]
          format_citation(entryarray)
        end
        
        # for the bibtex syntax \cites (multiple sources)
        rx_cites = /CITES(.*?)} /
        @line.gsub!(rx_cites) do |string|
          entries = string.scan(/\[.*?}/)
          entryarray = []
          entries.each do |entry|
            if entry.include?("][")
              # with prenote
              rx_cites_fields = /\[([^\]]*?)\]\[([^\]]*?)\]{(\w+?)}/
              entryarray += entry.scan(rx_cites_fields).collect do |fields|
                prenote = fields[0]
                postnote = fields[1]
                bibkey = fields[2]
                format_citation_entry(bibkey, postnote, prenote)
              end
            else
              # without prenote
              rx_cites_fields = /\[(.*?)\]{(\w*?)}/
              entryarray += entry.scan(rx_cites_fields).collect do |fields|
                prenote = nil
                postnote = fields[0]
                bibkey = fields[1]
                format_citation_entry(bibkey, postnote, prenote)
              end
            end

          end
          "#{ format_citation(entryarray) } "
        end
      end
    end
    
    # this joins multiple citation entries together, and wraps it either as a <sup> or as a footnote
    def format_citation(entryarray)
      if @line.include?("]:")
        # if this is a citation within a footnote, emulate biblatex's behavior by citing inline.
        type = "classic"
      else
        # otherwise, use the citation style defined by the user in metadata.yml
        type = @metadata['ebook_citation_style']
        # fallback
        type ||= 'footnote'
      end
      joined_array = entryarray.join("; ")
      string = ""
      if type == 'superscript'
        string = "^[#{ joined_array }]^" # note: ^x^ is custom superscript syntax defined in HtmlProcessor, improve_typography method
      elsif type == 'footnote'
        string = "[^bibfootnote#{ Random.new.rand(1..5000000) }]"
        @bibliography_footnotes << "#{ string }: #{ joined_array }"
      elsif type == 'classic'
        string = "[#{ joined_array }] "
      else
        return "===format_citation error: only 'superscript' and :footnote types allowed, #{ type.inspect } given==="
      end
      return string
    end
    
    # this formats a single citation entry
    def format_citation_entry(bibkey, postnote, prenote)
      single_page_abbreviation = "#{ @metadata['ebook_citation_page_one'] } "
      multiple_page_abbreviation = "#{ @metadata['ebook_citation_page_other'] } "
      
      if postnote.blank?
        postnote = ""
      elsif postnote.include?("-") or postnote.include?(",")
        # desginate several pages, i.e. pp. 101-103
        postnote = multiple_page_abbreviation + postnote
      else
        # single page, ie. p. 101
        postnote = single_page_abbreviation + postnote
      end
      
      idx = @used_and_available_citation_keys.index(bibkey)
      
      if idx.nil?
        return "Missing definition for entry <b>#{ bibkey }</b>"
      end

      type = @metadata['ebook_citation_style']
      type ||= 'footnote' # fallback

      if @bibliography_database && ( type == "footnote" || type == "superscript" )
        
        
        citeproc_hash = @bibliography_database[bibkey].to_citeproc
        
        if citeproc_hash["author"] && citeproc_hash["author"].size > 0
          authorarray = citeproc_hash["author"].collect do |author|
            familyname = author["family"]
            if familyname[0] == "{"
              # this is an {{ }} entry, not supported by ruby-citeproc. so we fix it here
              familyname.gsub("{", "").gsub("}", "")
            else
              "name(#{ author["family"] })"
            end
          end
          authornames = authorarray.join(" & ")
        
        elsif citeproc_hash["editor"] && citeproc_hash["editor"].size > 0
          # for books that don't have an author, only an editor, e.g. encyclopedias. This again emulates biblatex's behavior for Kindle.
          authornames = "name(#{ citeproc_hash["editor"][0]["family"] })"
        end
        
        case citeproc_hash["type"]
        when "book"
          # the book title will be formatted. The title() syntax will be broken down into proper HTML formatting by HtmlProcessor, and into proper Latex formatting by LatexProcessor
          title = "title(#{ citeproc_hash["title"] })"
          
        when "article-journal", "online"
          # article title is in quotations, volume/book title is formatted
          title = "\"#{ citeproc_hash["title"] }\""
          unless citeproc_hash["volume"].blank?
            title += ", title(#{ citeproc_hash["volume"] })"
          end
          unless citeproc_hash["issue"].blank?
            title += ", Issue #{ citeproc_hash["issue"] }"
          end
          
        else
          title = citeproc_hash["title"]
        end
        
        if citeproc_hash["URL"]
          url = citeproc_hash["URL"]
        end
        
        citation_text_contents = [
          authornames,
          title,
          url
        ]
        citation_text_contents.delete(nil)
        citation_text = citation_text_contents.join(", ")
        if postnote.blank?
          return "#{ prenote } #{ citation_text }."
        else
          return "#{ prenote } #{ citation_text }, #{ postnote }"
        end
      
      elsif type == "classic"
        citation_number = idx + 1
        return "#{ prenote } #{ citation_number } #{ postnote }"
      end
    end
    
    def run_custom_filter(txt, filename)
      function = @v8_object['kramdown_postprocessing']
      return function.methodcall(function, txt, filename)
    end
  end
end
