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
  class EbookRenderer
    def initialize(inpath, metadata, language=nil, rails_resources_url='', projectname='unnamed')
      Publishr.log "[Publishr::EbookRenderer] initialize"
      @inpath = inpath
      if language and not language.empty?
        @language = language.include?('.') ? language : ".#{language}" # inside of the whole publishr gem, @language must be prefixed with a dot
      else
        @language = nil
      end
      @name = projectname
      @outpath = File.join(inpath,'epub')
      @metadata = metadata
      @gempath = Publishr::Project.gempath
      @rails_resources_url = rails_resources_url
      
      @kramdown_processor = Publishr::KramdownProcessor.new(@inpath, @metadata, @language)
      @html_processor = HtmlProcessor.new(@inpath, @metadata, @language, @rails_resources_url)
      
      @bibliography_database = @kramdown_processor.bibliography_database
      @used_and_available_citation_keys =  @kramdown_processor.used_and_available_citation_keys

      @html_files = []
      @image_files = []
    end

    def render
      Publishr.log "[Publishr::EbookRenderer] render"
      make_epub_directory_structure
      render_htmls
      compile_xmls
    end

    def make_epub_directory_structure
      Publishr.log "[Publishr::EbookRenderer] make_epub_directory_structure"
      # clean everything
      FileUtils.rm_rf @outpath
      
      # copy epub skeleton and images to outpath
      FileUtils.cp_r File.join(@gempath,'lib','epub_skeleton'), @outpath
      Helper.copy_images(@inpath, @outpath, @language, 'jpg')

      # copy localized cover image to outpath
      FileUtils.cp File.join(@inpath,"cover#{ @language }.jpg"), File.join(@outpath,'cover.jpg')

      # copy localized overriding css file to outpath if exists
      if File.exists?(File.join(@inpath,"override#{ @language }.css")) 
        FileUtils.cp(File.join(@inpath,"override#{ @language }.css"), File.join(@outpath, "override.css"))
      end
    end

    def render_htmls
      Publishr.log "[Publishr::EbookRenderer] render_htmls"
      (Dir[File.join(@inpath, "*#{ @language }.page")] + ["covertext#{ @language }.txt", "frontmatter#{ @language }.txt", "toc#{ @language }.txt"]).sort.each do |infilepath|
        Publishr.log "[Publishr::EbookRenderer] render_htmls: rendering #{ infilepath }"
          
        kramdown_options = @metadata['kramdown_options']
        if @metadata['continuous_footnote_numbering_ebook'] == true
          previous_footnote_count, previous_citation_count = Publishr::Helper.get_footnote_count_upto_file(@inpath, @language, File.basename(infilepath))
        else
          previous_footnote_count = 0
          previous_citation_count = 0
        end
        
        footnote_start = 1 + previous_footnote_count
        if @metadata['ebook_citation_style'] == "footnote"
          footnote_start += previous_citation_count
        end
      
        kramdown_options.merge!({
          :template => File.join(@gempath, 'lib', 'epub_templates', 'kramdown.html'),
          :footnote_nr => footnote_start
        })
          
        content = File.open(infilepath, 'r').read
        if infilepath.include? '.page'
          kramdown = Helper.strip_webgen_header_from_page_file(content)
        else
          kramdown = content
        end
        preprocessed_kramdown = @kramdown_processor.transform_superset(kramdown, File.basename(infilepath))
        html = Kramdown::Document.new(preprocessed_kramdown, kramdown_options).to_html
        ebook_html = @html_processor.transform_for_ebook(html, File.basename(infilepath))
        outfilepath = File.join(@outpath, File.basename(infilepath).gsub(/(.*).(txt|page)/, '\1.html'))
        File.open(outfilepath, 'w'){ |f| f.write ebook_html }
      end
      
      @html_files << File.join(@outpath,"covertext#{ @language }.html")
      @html_files << File.join(@outpath,"frontmatter#{ @language }.html")
      @html_files << File.join(@outpath,"toc#{ @language }.html")
      @html_files += Dir[File.join(@outpath,'*.html')].sort
      
      if @bibliography_database
        make_bibliography
        @html_files << File.join(@outpath,"bibliography#{ @language }.html")
      end
      
      @html_files.uniq!
    end
    
    def make_bibliography
      Publishr.log "[Publishr::EbookRenderer] make_bibliography"
      erb = File.open(File.join(@gempath,'lib','epub_templates','kramdown.html'),'r').read
      @body = "<h1>#{ @metadata['ebook_citation_heading'] }</h1>"
      
      @body += @used_and_available_citation_keys.collect do |k|
        Publishr.log "[Publishr::EbookRenderer] make_bibliography: processing key #{ k }"
        
        citeproc_hash = @bibliography_database[k].to_citeproc
        citation_text = CiteProc.process(@bibliography_database[k].to_citeproc, :style => "chicago-fullnote-bibliography", :format => :html)
        
        # ugly hack to remove {} from institutional author names which are specified as {{name}}.
        # biblatex recogizes this correctly but is missed by the CiteProc gem. apologies, but no time to dig into those gems now.
        citation_text = citation_text.gsub("{", "").gsub("}", "")
        
        # ugly hack to fix stray uppercases after apostrophes like "A Soldier'S view". Seems to be a bug in the CiteProc gem.
        citation_text = citation_text.gsub(/'(\w)/) {"'#{$1.downcase}"}
        
        
        # see gems
        # https://github.com/inukshuk/citeproc-ruby
        # https://github.com/inukshuk/citeproc
        # https://github.com/inukshuk/csl-ruby
        # https://github.com/citation-style-language/styles
        
        #chicago-author-date
        "<p><b>[#{ @used_and_available_citation_keys.index(k) + 1}]</b> #{ citation_text }</p>"
        
      end.join("\n")
      
      f = File.open(File.join(@outpath, "bibliography#{ @language }.html"), 'w')
      f.write ERB.new(erb).result binding
      f.close
    end

    def compile_xmls
      Publishr.log "[Publishr::EbookRenderer] compile_xmls"
      File.open(File.join(@outpath,'content.opf'),'w'){ |f| f.write render_content_opf }
      File.open(File.join(@outpath,'toc.ncx'),'w'){ |f| f.write render_toc_ncx     }
      Dir.chdir @outpath
      filename = File.join(@inpath,"#{ @name }#{ @language }.epub")
      `zip -X0 #{ filename } mimetype`
      `zip -Xur9D #{ filename } *`
    end

    def render_content_opf
      Publishr.log "[Publishr::EbookRenderer] render_content_opf"
      erb = File.open(File.join(@gempath,'lib','epub_templates','content.opf.erb'),'r').read
      spine_items = render_spine_items
      manifest_items = render_manifest_items
      ERB.new(erb).result binding
    end

    def render_toc_ncx
      Publishr.log "[Publishr::EbookRenderer] render_toc_ncx"
      erb = File.open(File.join(@gempath,'lib','epub_templates','toc.ncx.erb'),'r').read
      nav_points = render_nav_points
      ERB.new(erb).result binding
    end

    def render_nav_points
      Publishr.log "[Publishr::EbookRenderer] render_nav_points"
      erb = File.open(File.join(@gempath,'lib','epub_templates','nav_points.erb'),'r').read
      results = []
      i = 0
      @html_files.each do |h|
        filename = File.basename(h)
        id = filename.gsub '.',''
        i += 1
        results << (ERB.new(erb).result binding)
      end
      results.join("\n")
    end

    def render_manifest_items
      Publishr.log "[Publishr::EbookRenderer] render_manifest_items"
      image_files = Dir[File.join(@outpath,'*.jpg')]
      erb = File.open(File.join(@gempath,'lib','epub_templates','manifest_items.erb'),'r').read
      results = []
      (@html_files + image_files).each do |h|
        filename = File.basename(h)
        id = filename.gsub '.',''
        mediatype = case File.extname(h) 
          when '.html' then 'application/xhtml+xml'
          when '.jpg' then 'image/jpeg'
          when '.png' then 'image/png'
        end
        results << (ERB.new(erb).result binding)
      end
      results.join("\n")
    end

    def render_spine_items
      Publishr.log "[Publishr::EbookRenderer] render_spine_items"
      erb = File.open(File.join(@gempath,'lib','epub_templates','spine_items.erb'),'r').read
      results = []
      @html_files.each do |h|
        id = File.basename(h).gsub '.',''
        results << (ERB.new(erb).result binding)
      end
      results.join("\n")
    end
  end
end
